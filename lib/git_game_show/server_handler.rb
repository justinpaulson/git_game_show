module GitGameShow
  # Coordinates the various components of the game server
  class ServerHandler
    attr_reader :game_state, :player_manager, :question_manager

    def initialize(port:, password:, rounds:, repo:)
      @port = port
      @password = password
      @rounds = rounds
      @repo = repo

      # Initialize core components
      @game_state = GameState.new(rounds)
      @player_manager = PlayerManager.new
      @mini_game_loader = MiniGameLoader.new

      # Initialize UI components
      @renderer = Renderer.new
      @sidebar = Sidebar.new(@renderer)
      @console = Console.new(self, @renderer)

      # Initialize network components - passing self allows circular reference
      @message_handler = MessageHandler.new(@player_manager, @game_state, @renderer, self)
      @message_handler.set_password(password)
      @server = Server.new(port, @message_handler)

      # Finally initialize the question manager
      @question_manager = QuestionManager.new(@game_state, @player_manager)
    end

    def start_with_ui(join_link = nil)
      # Store join link as instance variable so it's accessible throughout the class
      @join_link = join_link

      # Setup UI
      @renderer.setup
      @renderer.draw_welcome_banner
      @renderer.draw_join_link(@join_link) if @join_link
      @sidebar.draw_header
      @sidebar.update_player_list(@player_manager.player_names, @player_manager.scores)
      @renderer.draw_command_prompt

      # Start event machine
      EM.run do
        # Start the server
        @server.start
        # Setup console commands
        @console.setup_command_handler
      end
    end

    # Game lifecycle methods
    def handle_start_command
      if @player_manager.player_count < 1
        @renderer.log_message("Need at least one player to start", :red)
        return
      end

      # If players are in an ended state, reset them first
      if @game_state.ended?
        @renderer.log_message("Resetting players from previous game...", :light_black)
        broadcast_message({
          type: MessageType::GAME_RESET,
          message: "Get ready! The host is starting a new game..."
        })
        # Give players a moment to see the reset message
        sleep(1)
      end

      # Start the game
      if @game_state.start_game
        broadcast_message({
          type: MessageType::GAME_START,
          rounds: @rounds,
          players: @player_manager.player_names
        })

        @renderer.log_message("Game started with #{@player_manager.player_count} players", :green)
        start_next_round
      end
    end

    def handle_end_command
      if @game_state.playing?
        @renderer.log_message("Ending game early...", :yellow)
        end_game
      elsif @game_state.ended?
        @renderer.log_message("Game already ended. Type 'start' to begin a new game.", :yellow)
      else
        @renderer.log_message("No game in progress to end", :yellow)
      end
    end

    def handle_reset_command
      if @game_state.ended?
        @renderer.log_message("Manually resetting all players to waiting room state...", :yellow)

        # Send a game reset message to all players
        broadcast_message({
          type: MessageType::GAME_RESET,
          message: "Game has been reset by the host. Waiting for a new game to start."
        })

        # Update game state
        @game_state.reset_game
      else
        @renderer.log_message("Can only reset after a game has ended", :yellow)
      end
    end

    def start_next_round
      @game_state.start_next_round(@mini_game_loader.select_next_mini_game)

      # Check if we've completed all rounds
      if @game_state.current_round > @rounds
        @renderer.log_message("All rounds completed! Showing final scores...", :green)
        EM.next_tick { end_game } # Use next_tick to ensure it runs after current operations
        return
      end

      # Announce new round
      broadcast_message({
        type: 'round_start',
        round: @game_state.current_round,
        total_rounds: @rounds,
        mini_game: @game_state.current_mini_game.class.name,
        description: @game_state.current_mini_game.class.description,
        example: @game_state.current_mini_game.class.example
      })

      # Generate questions for this round
      @question_manager.generate_questions(@repo)

      @renderer.log_message("Starting round #{@game_state.current_round}: #{@game_state.current_mini_game.class.name}", :cyan)

      # Start the first question after a short delay
      EM.add_timer(3) do
        ask_next_question
      end
    end

    def ask_next_question
      return if @game_state.current_question_index >= @game_state.round_questions.size

      # Log information for debugging
      @renderer.log_message("Preparing question #{@game_state.current_question_index + 1} of #{@game_state.round_questions.size}", :cyan)

      # Prepare the question
      @game_state.prepare_next_question
      current_question = @game_state.current_question

      # Get the appropriate timeout value
      timeout = @question_manager.question_timeout

      # Prepare question data
      begin
        question_data = {
          type: MessageType::QUESTION,
          question_id: @game_state.current_question_id.to_s,
          question: current_question[:question].to_s,
          options: current_question[:options] || [],
          timeout: timeout,
          round: @game_state.current_round.to_i,
          question_number: (@game_state.current_question_index + 1).to_i,
          total_questions: @game_state.round_questions.size.to_i
        }

        # Add additional question data safely
        # Add question_type if it's a special question type (like ordering)
        if current_question && current_question[:question_type]
          question_data[:question_type] = current_question[:question_type].to_s
        end

        # Add commit info if available (for AuthorQuiz)
        if current_question && current_question[:commit_info]
          # Make a safe copy to avoid potential issues with the original object
          if current_question[:commit_info].is_a?(Hash)
            safe_commit_info = {}
            current_question[:commit_info].each do |key, value|
              safe_commit_info[key.to_s] = value.to_s
            end
            question_data[:commit_info] = safe_commit_info
          else
            question_data[:commit_info] = current_question[:commit_info].to_s
          end
        end

        # Add context if available (for BlameGame)
        if current_question && current_question[:context]
          question_data[:context] = current_question[:context].to_s
        end
      rescue => e
        @renderer.log_message("Error preparing question data: #{e.message}", :red)
        # Create a minimal fallback question
        question_data = {
          type: MessageType::QUESTION,
          question_id: @game_state.current_question_id.to_s,
          question: "Question #{@game_state.current_question_index + 1}",
          options: ["Option 1", "Option 2", "Option 3", "Option 4"],
          timeout: timeout,
          round: @game_state.current_round.to_i,
          question_number: (@game_state.current_question_index + 1).to_i,
          total_questions: @game_state.round_questions.size.to_i
        }
      end

      # Don't log detailed question info to prevent author lists from showing
      @renderer.log_message("Question #{@game_state.current_question_index + 1}/#{@game_state.round_questions.size}", :cyan)
      @renderer.log_message("Broadcasting question to players...", :cyan)
      broadcast_message(question_data)

      # Set a timer for question timeout
      EM.add_timer(timeout) do
        @renderer.log_message("Question timeout (#{timeout}s) - evaluating", :yellow)
        evaluate_answers
      end
    end

    def evaluate_answers
      # Delegate to question manager
      evaluation = @question_manager.evaluate_answers
      return unless evaluation

      # Update player list in sidebar to reflect new scores
      @sidebar.update_player_list(@player_manager.player_names, @player_manager.scores)

      # Broadcast results to all players
      broadcast_message({
        type: MessageType::ROUND_RESULT,
        question: evaluation[:question],
        results: evaluation[:results],
        correct_answer: evaluation[:question][:formatted_correct_answer] || evaluation[:question][:correct_answer],
        scores: @player_manager.sorted_scores
      })

      # Log current scores for the host
      @renderer.log_message("Current scores:", :cyan)
      @player_manager.sorted_scores.each do |player, score|
        truncated_name = player.length > 15 ? "#{player[0...12]}..." : player
        @renderer.log_message("#{truncated_name}: #{score} points", :light_blue)
      end

      # Move to next question or round
      @game_state.move_to_next_question

      if @game_state.current_question_index >= @game_state.round_questions.size
        # End of round
        EM.add_timer(GitGameShow::DEFAULT_CONFIG[:transition_delay]) do
          start_next_round
        end
      else
        # Next question - use mini-game specific timing if available
        display_time = @question_manager.question_display_time

        @renderer.log_message("Next question in #{display_time} seconds...", :cyan)
        EM.add_timer(display_time) do
          ask_next_question
        end
      end
    end

    def end_game
      @game_state.end_game

      # Get winner and scores
      winner = @player_manager.top_player
      scores = @player_manager.scores

      # Notify all players
      broadcast_message({
        type: MessageType::GAME_END,
        winner: winner ? winner[0].to_s : "",
        scores: @player_manager.sorted_scores
      })

      # Display the final results
      @renderer.draw_game_over(winner, scores)

      # Reset for next game
      @game_state.reset_game
      @player_manager.reset_scores

      # Update sidebar
      @sidebar.update_player_list(@player_manager.player_names, @player_manager.scores)
      @renderer.log_message("Game ended! Type 'start' to play again or 'exit' to quit.", :cyan)
    end

    def broadcast_message(message, exclude: nil)
      @server.broadcast_message(message, exclude: exclude)
    end

    def broadcast_scoreboard
      broadcast_message({
        type: MessageType::SCOREBOARD,
        scores: @player_manager.sorted_scores
      })
    end
  end
end
