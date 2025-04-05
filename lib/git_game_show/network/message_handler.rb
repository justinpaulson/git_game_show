module GitGameShow
  # Handles WebSocket messages
  class MessageHandler
    def initialize(player_manager, game_state, renderer, server_handler)
      @player_manager = player_manager
      @game_state = game_state
      @renderer = renderer
      @server_handler = server_handler
      @password = nil # Will be set through setter
    end

    def set_password(password)
      @password = password
    end

    def handle_message(ws, msg)
      begin
        data = JSON.parse(msg)
        case data['type']
        when MessageType::JOIN_REQUEST
          handle_join_request(ws, data)
        when MessageType::ANSWER
          handle_answer(data)
        when MessageType::CHAT
          @server_handler.broadcast_message(data)
        else
          @renderer.log_message("Unknown message type: #{data['type']}", :red)
        end
      rescue JSON::ParserError => e
        @renderer.log_message("Invalid message format: #{e.message}", :red)
      rescue => e
        @renderer.log_message("Error processing message: #{e.message}", :red)
      end
    end

    def handle_player_disconnect(ws)
      # Find the player who disconnected
      player_name = @player_manager.find_player_by_ws(ws)
      return unless player_name

      # Remove the player
      @player_manager.remove_player(player_name)

      # Update the sidebar to reflect the player leaving
      @server_handler.instance_variable_get(:@sidebar)&.update_player_list(@player_manager.player_names, @player_manager.scores)

      # Log message for player leaving
      @renderer.log_message("🔴 #{player_name} has left the game", :yellow)

      # Notify other players
      @server_handler.broadcast_message({
        type: 'player_left',
        name: player_name,
        players: @player_manager.player_names
      })
    end

    def broadcast(json_message, exclude = nil)
      @player_manager.players.each do |player_name, ws|
        # Skip excluded player if specified
        next if exclude && player_name == exclude

        # Skip nil websockets
        next unless ws

        # Send with error handling for each individual player
        begin
          ws.send(json_message)
        rescue => e
          @renderer.log_message("Error sending to #{player_name}: #{e.message}", :yellow)
        end
      end
    end

    private

    def handle_join_request(ws, data)
      player_name = data['name']
      sent_password = data['password']

      response = {
        type: MessageType::JOIN_RESPONSE
      }

      # Check if game is already in progress
      if @game_state.playing?
        response.merge!(success: false, message: "Game is already in progress")
      # Validate password
      elsif sent_password != @password
        response.merge!(success: false, message: "Incorrect password")
      # Check for duplicate names
      elsif @player_manager.player_exists?(player_name)
        response.merge!(success: false, message: "Player name already taken")
      else
        # Add player to the game
        @player_manager.add_player(player_name, ws)

        # Update the sidebar to show the new player
        @server_handler.instance_variable_get(:@sidebar)&.update_player_list(@player_manager.player_names, @player_manager.scores)

        # Include current player list in the response
        response.merge!(
          success: true,
          message: "Successfully joined the game",
          players: @player_manager.player_names
        )

        # Notify all existing players about the new player
        @server_handler.broadcast_message({
          type: 'player_joined',
          name: player_name,
          players: @player_manager.player_names
        }, exclude: player_name)

        # Log message for player joining
        @renderer.log_message("🟢 #{player_name} has joined the game", :green)
      end

      ws.send(response.to_json)
    end

    def handle_answer(data)
      return unless @game_state.playing?

      player_name = data['name']
      answer = data['answer']
      question_id = data['question_id']

      # Make sure the answer is for the current question
      return unless question_id == @game_state.current_question_id

      # Don't allow duplicate answers
      return if @game_state.player_answers.dig(player_name, :answered)

      # Calculate time taken to answer
      time_taken = Time.now - @game_state.question_start_time

      # Get current question
      current_question = @game_state.current_question

      # Handle nil answer (timeout) differently
      points = 0

      if answer.nil?
        # For timeouts, set a special "TIMEOUT" answer with 0 points
        @game_state.record_player_answer(player_name, "TIMEOUT", time_taken, false, 0)

        # Send timeout feedback to the player
        feedback = {
          type: MessageType::ANSWER_FEEDBACK,
          answer: "TIMEOUT",
          correct: false,
          correct_answer: current_question[:correct_answer],
          points: points
        }
        @player_manager.get_ws(player_name)&.send(feedback.to_json)

        # Log the timeout
        truncated_name = player_name.length > 15 ? "#{player_name[0...12]}..." : player_name
        @renderer.log_message("#{truncated_name} timed out after #{time_taken.round(2)}s ⏰", :yellow)
      else
        # Regular answer processing
        # For ordering quizzes, we'll calculate points in evaluate_answers
        if current_question[:question_type] == 'ordering'
          # Just store the answer and time, points will be calculated in evaluate_answers
          correct = false # Will be properly set during evaluation

          # Get the mini-game to evaluate this answer for points
          mini_game = @game_state.current_mini_game
          points = mini_game.evaluate_answers(
            current_question,
            {player_name => {answer: answer, time_taken: time_taken}}
          ).values.first[:points]
        else
          # For regular quizzes, calculate points immediately
          correct = answer == current_question[:correct_answer]
          points = 0

          if correct
            points = 10 # Base points for correct answer

            # Bonus points for fast answers
            if time_taken < 5
              points += 5
            elsif time_taken < 10
              points += 3
            end
          end
        end

        # Store the answer
        @game_state.record_player_answer(player_name, answer, time_taken, correct, points)

        # Send immediate feedback to this player only
        send_answer_feedback(player_name, answer, correct, current_question, points)

        # Log this answer - ensure the name is not too long
        truncated_name = player_name.length > 15 ? "#{player_name[0...12]}..." : player_name
        if current_question[:question_type] == 'ordering'
          @renderer.log_message("#{truncated_name} submitted ordering in #{time_taken.round(2)}s ⏱️", :cyan)
        else
          @renderer.log_message("#{truncated_name} answered in #{time_taken.round(2)}s: #{correct ? "Correct ✓" : "Wrong ✗"}", correct ? :green : :red)
        end
      end

      # Check if all players have answered
      check_all_answered
    end

    def send_answer_feedback(player_name, answer, correct, question, points=0)
      # Send feedback only to the player who answered
      ws = @player_manager.get_ws(player_name)
      return unless ws

      feedback = {
        type: MessageType::ANSWER_FEEDBACK,
        answer: answer,
        correct: correct,
        correct_answer: question[:correct_answer],
        points: points # Include points in the feedback
      }

      # For ordering quizzes, we can't determine correctness immediately
      if question[:question_type] == 'ordering'
        feedback[:correct] = nil # nil means "scoring in progress"
        # Keep the points value that was calculated earlier
        feedback[:message] = "Ordering submitted. Points calculated based on your ordering."
      end

      ws.send(feedback.to_json)
    end

    def check_all_answered
      # If all players have answered, log it but WAIT for the full timeout
      if @game_state.player_answers.keys.size == @player_manager.player_count
        timeout_sec = GitGameShow::DEFAULT_CONFIG[:question_timeout]
        @renderer.log_message("All players have answered - waiting for timeout (#{timeout_sec}s)", :cyan)
      end
    end
  end
end
