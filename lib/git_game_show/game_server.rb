module GitGameShow
  class GameServer
    attr_reader :port, :password, :rounds, :repo, :players, :current_round, :game_state

    def initialize(port:, password:, rounds:, repo:)
      @port = port
      @password = password
      @rounds = rounds
      @repo = repo
      @players = {}  # WebSocket connections by player name
      @scores = {}   # Player scores
      @current_round = 0
      @game_state = :lobby  # :lobby, :playing, :ended
      @mini_games = load_mini_games
      @current_mini_game = nil
      @round_questions = []
      @current_question_index = 0
      @question_start_time = nil
      @player_answers = {}
      @used_mini_games = []  # Track which mini-games have been used
      @available_mini_games = []  # Mini-games still available in the current cycle
    end

    def start
      EM.run do
        setup_server

        # Setup console commands for the host
        setup_console_commands

        puts "Server running at ws://0.0.0.0:#{port}".colorize(:green)
      end
    end

    def start_with_ui(join_link = nil)
      # Display UI
      @show_host_ui = true
      @join_link = join_link
      @message_log = []
      @players = {}
      @cursor = TTY::Cursor

      # Get terminal dimensions
      @terminal_width = `tput cols`.to_i rescue 80
      @terminal_height = `tput lines`.to_i rescue 24

      # Calculate layout
      @main_width = (@terminal_width * 0.7).to_i
      @sidebar_width = @terminal_width - @main_width - 3 # 3 for border

      # The fixed line for command input (near bottom of screen)
      @command_line = @terminal_height - 3

      # Clear screen and hide cursor
      print @cursor.clear_screen
      print @cursor.hide

      # Draw initial UI
      draw_ui_frame
      draw_welcome_banner
      draw_join_link
      draw_sidebar
      draw_command_prompt

      # Set up buffer for events
      @event_buffer = []

      # Start the server
      EM.run do
        setup_server
        setup_fixed_console_commands
      end
    end

    def draw_ui_frame
      # Clear screen
      print @cursor.clear_screen

      # Draw horizontal divider line between main area and command area
      print @cursor.move_to(0, @command_line - 1)
      print "═" * (@terminal_width - @sidebar_width - 3) + "╧" + "═" * (@sidebar_width + 2)

      # Draw vertical divider line between main area and sidebar
      print @cursor.move_to(@main_width, 0)
      print "│"
      print @cursor.move_to(@main_width, 1)
      print "│"
      print @cursor.move_to(@main_width, 2)
      print "╞═"
      (3...@command_line-1).each do |line|
        print @cursor.move_to(@main_width, line)
        print "│"
      end
    end

    def draw_welcome_banner
      # Position cursor at top left
      lines = [
        " ██████╗ ".colorize(:red) + "  ██████╗ ".colorize(:green) + "  █████╗".colorize(:blue),
        "██╔════╝ ".colorize(:red) + " ██╔════╝ ".colorize(:green) + " ██╔═══╝".colorize(:blue),
        "██║  ███╗".colorize(:red) + " ██║  ███╗".colorize(:green) + " ███████╗".colorize(:blue),
        "██║   ██║".colorize(:red) + " ██║   ██║".colorize(:green) + " ╚════██║".colorize(:blue),
        "╚██████╔╝".colorize(:red) + " ╚██████╔╝".colorize(:green) + " ██████╔╝".colorize(:blue),
        " ╚═════╝ ".colorize(:red) + "  ╚═════╝ ".colorize(:green) + " ╚═════╝ ".colorize(:blue),
      ]

      start_y = 1
      lines.each_with_index do |line, i|
        print @cursor.move_to((@main_width - 28) / 2, start_y + i)
        print line
      end
    end

    def draw_join_link
      # Copy the join link to clipboard
      Clipboard.copy(@join_link)

      link_box_width = [@join_link.length + 6, @main_width - 10].min
      start_x = (@main_width - link_box_width) / 2
      start_y = 8

      print @cursor.move_to(start_x, start_y)
      print "╭" + "─" * (link_box_width - 2) + "╮"

      print @cursor.move_to(start_x, start_y + 1)
      print "│" + " Join Link (Copied to Clipboard) ".center(link_box_width - 2).colorize(:green) + "│"

      print @cursor.move_to(start_x, start_y + 2)
      print "│" + @join_link.center(link_box_width - 2).colorize(:yellow) + "│"

      print @cursor.move_to(start_x, start_y + 3)
      print "╰" + "─" * (link_box_width - 2) + "╯"

      # Also log that the link was copied
      log_message("Join link copied to clipboard", :green)
    end

    def draw_sidebar
      # Draw sidebar header
      print @cursor.move_to(@main_width + 2, 1)
      print "Players".colorize(:cyan)

      print @cursor.move_to(@main_width + 2, 2)
      print "═" * (@sidebar_width - 2)

      update_player_list
    end

    def update_player_list
      # Clear player area
      (3..(@command_line-3)).each do |line|
        print @cursor.move_to(@main_width + 2, line)
        print " " * (@sidebar_width - 2)
      end

      # Show player count
      print @cursor.move_to(@main_width + 2, 3)
      print "Total: #{@players.size} player(s)".colorize(:yellow)

      # Calculate available space for the player list
      max_visible_players = @command_line - 8 # Allow space for headers, counts and scrolling indicators

      # List players with scrolling if needed
      if @players.empty?
        print @cursor.move_to(@main_width + 2, 5)
        print "Waiting for players...".colorize(:light_black)
      else
        # Show scrolling indicator if needed
        if @players.size > max_visible_players
          print @cursor.move_to(@main_width + 2, 4)
          print "Showing #{max_visible_players} of #{@players.size}:".colorize(:light_yellow)
        end

        # Determine which players to display (for now, show first N players)
        visible_players = @players.keys.take(max_visible_players)

        # Display visible players
        visible_players.each_with_index do |name, index|
          print @cursor.move_to(@main_width + 2, 5 + index)
          # Truncate long names
          truncated_name = name.length > (@sidebar_width - 6) ?
                           "#{name[0...(@sidebar_width-9)]}..." :
                           name

          if index < 9
            print "#{index + 1}. #{truncated_name}".colorize(:light_blue)
          else
            print "#{index + 1}. #{truncated_name}".colorize(:light_blue)
          end
        end

        # If there are more players than can be shown, add an indicator
        if @players.size > max_visible_players
          print @cursor.move_to(@main_width + 2, 5 + max_visible_players)
          print "... and #{@players.size - max_visible_players} more".colorize(:light_black)
        end
      end

      # Return cursor to command prompt
      draw_command_prompt
    end

    def log_message(message, color = :white)
      # Add message to log
      @message_log << {text: message, color: color}

      # Keep only last few messages
      @message_log = @message_log.last(15) if @message_log.size > 15

      # Redraw message area
      draw_message_area

      # Return cursor to command prompt
      draw_command_prompt
    end

    def draw_message_area
      # Calculate message area dimensions
      message_area_start = 18
      message_area_height = @command_line - message_area_start - 2

      # Clear message area
      (message_area_start..(@command_line-2)).each do |line|
        print @cursor.move_to(1, line)
        print " " * (@main_width - 2)
      end

      # Draw most recent messages
      display_messages = @message_log.last(message_area_height)
      display_messages.each_with_index do |msg, index|
        print @cursor.move_to(1, message_area_start + index)
        # Truncate message to fit within main width to prevent overflow
        truncated_text = msg[:text][0...(@main_width - 3)]
        print truncated_text.colorize(msg[:color])
      end

      # No need to call draw_command_prompt here as it's already called by log_message
    end

    def draw_command_prompt
      # Clear command line and two lines below to prevent commit info bleeding
      print @cursor.move_to(0, @command_line)
      print " " * @terminal_width
      print @cursor.move_to(0, @command_line + 1)
      print " " * @terminal_width
      print @cursor.move_to(0, @command_line + 2)
      print " " * @terminal_width

      # Draw command prompt
      print @cursor.move_to(0, @command_line)
      print "Command> ".colorize(:green)

      # Position cursor after prompt
      print @cursor.move_to(9, @command_line)
      print @cursor.show
    end

    def display_welcome_banner
      banner = <<-BANNER.colorize(:green)
 ██████╗ ██╗████████╗     ██████╗  █████╗ ███╗   ███╗███████╗
██╔════╝ ██║╚══██╔══╝    ██╔════╝ ██╔══██╗████╗ ████║██╔════╝
██║  ███╗██║   ██║       ██║  ███╗███████║██╔████╔██║█████╗
██║   ██║██║   ██║       ██║   ██║██╔══██║██║╚██╔╝██║██╔══╝
╚██████╔╝██║   ██║       ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗
 ╚═════╝ ╚═╝   ╚═╝        ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝
      BANNER
      banner.each{|line| puts line.center(80)}
    end

    private

    def setup_server
      WebSocket::EventMachine::Server.start(host: '0.0.0.0', port: port) do |ws|
        ws.onopen do
          # Connection is logged when a player successfully joins
        end

        ws.onmessage do |msg|
          handle_message(ws, msg)
        end

        ws.onclose do
          handle_player_disconnect(ws)
        end
      end
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
          broadcast_message(data)
        else
          puts "Unknown message type: #{data['type']}".colorize(:red)
        end
      rescue JSON::ParserError => e
        puts "Invalid message format: #{e.message}".colorize(:red)
      rescue => e
        puts "Error processing message: #{e.message}".colorize(:red)
      end
    end

    def handle_join_request(ws, data)
      player_name = data['name']
      sent_password = data['password']

      response = {
        type: MessageType::JOIN_RESPONSE
      }

      # Check if game is already in progress
      if @game_state != :lobby
        response.merge!(success: false, message: "Game is already in progress")
      # Validate password
      elsif sent_password != password
        response.merge!(success: false, message: "Incorrect password")
      # Check for duplicate names
      elsif @players.key?(player_name)
        response.merge!(success: false, message: "Player name already taken")
      else
        # Add player to the game
        @players[player_name] = ws
        @scores[player_name] = 0

        # Include current player list in the response
        response.merge!(
          success: true,
          message: "Successfully joined the game",
          players: @players.keys
        )

        # Notify all existing players about the new player
        broadcast_message({
          type: 'player_joined',
          name: player_name,
          players: @players.keys
        }, exclude: player_name)

        # Log message for player joining
        log_message("🟢 #{player_name} has joined the game", :green)
        # Update player list in sidebar
        update_player_list
      end

      ws.send(response.to_json)
    end

    def handle_player_disconnect(ws)
      # Find the player who disconnected
      player_name = @players.key(ws)
      return unless player_name

      # Remove the player
      @players.delete(player_name)

      # Log message for player leaving
      log_message("🔴 #{player_name} has left the game", :yellow)
      # Update player list in sidebar
      update_player_list

      # Notify other players
      broadcast_message({
        type: 'player_left',
        name: player_name,
        players: @players.keys
      })
    end

    def handle_answer(data)
      return unless @game_state == :playing

      player_name = data['name']
      answer = data['answer']
      question_id = data['question_id']

      # Make sure the answer is for the current question
      return unless question_id == @current_question_id

      # Don't allow duplicate answers
      return if @player_answers.dig(player_name, :answered)

      # Calculate time taken to answer
      time_taken = Time.now - @question_start_time

      # Get current question
      current_question = @round_questions[@current_question_index]

      # Handle nil answer (timeout) differently
      if answer.nil?
        # For timeouts, set a special "TIMEOUT" answer with 0 points
        @player_answers[player_name] = {
          answer: "TIMEOUT",
          time_taken: time_taken,
          answered: true,
          correct: false,
          points: 0
        }

        # Send timeout feedback to the player
        feedback = {
          type: MessageType::ANSWER_FEEDBACK,
          answer: "TIMEOUT",
          correct: false,
          correct_answer: current_question[:correct_answer],
          points: 0
        }
        @players[player_name]&.send(feedback.to_json)

        # Log the timeout
        truncated_name = player_name.length > 15 ? "#{player_name[0...12]}..." : player_name
        log_message("#{truncated_name} timed out after #{time_taken.round(2)}s ⏰", :yellow)
      else
        # Regular answer processing
        # For ordering quizzes, we'll calculate points in evaluate_answers
        # using the custom scoring systems in each mini-game
        if current_question[:question_type] == 'ordering'
          # Just store the answer and time, points will be calculated in evaluate_answers
          correct = false # Will be properly set during evaluation
          points = 0     # Will be properly set during evaluation
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
        @player_answers[player_name] = {
          answer: answer,
          time_taken: time_taken,
          answered: true,
          correct: correct,
          points: points
        }

        # Send immediate feedback to this player only
        send_answer_feedback(player_name, answer, correct, current_question, points)

        # Log this answer - ensure the name is not too long
        truncated_name = player_name.length > 15 ? "#{player_name[0...12]}..." : player_name
        if current_question[:question_type] == 'ordering'
          log_message("#{truncated_name} submitted ordering in #{time_taken.round(2)}s ⏱️", :cyan)
        else
          log_message("#{truncated_name} answered in #{time_taken.round(2)}s: #{correct ? "Correct ✓" : "Wrong ✗"}", correct ? :green : :red)
        end
      end

      # Check if all players have answered, regardless of timeout or manual answer
      check_all_answered
    end

    def send_answer_feedback(player_name, answer, correct, question, points=0)
      # Send feedback only to the player who answered
      ws = @players[player_name]
      return unless ws

      feedback = {
        type: MessageType::ANSWER_FEEDBACK,
        answer: answer,
        correct: correct,
        correct_answer: question[:correct_answer],
        points: points # Include points in the feedback
      }

      # For ordering quizzes, we can't determine correctness immediately
      # Instead we'll indicate that scoring will be calculated after timeout
      if question[:question_type] == 'ordering'
        feedback[:correct] = nil # nil means "scoring in progress"
        feedback[:points] = nil
        feedback[:message] = "Ordering submitted. Points will be calculated at the end of the round."
      end

      ws.send(feedback.to_json)
    end

    def check_all_answered
      # If all players have answered, log it but WAIT for the full timeout
      # This ensures consistent timing regardless of how fast people answer
      if @player_answers.keys.size == @players.size
        timeout_sec = GitGameShow::DEFAULT_CONFIG[:question_timeout]
        log_message("All players have answered - waiting for timeout (#{timeout_sec}s)", :cyan)
        # We don't immediately evaluate anymore - we wait for the timer
      end
    end

    def evaluate_answers
      # Safety checks
      return unless @current_mini_game
      return unless @round_questions && @current_question_index < @round_questions.size
      return if @question_already_evaluated

      @question_already_evaluated = true

      # Safety check - make sure we have a current question
      begin
        current_question = @round_questions[@current_question_index]
        return unless current_question # Skip if no current question
      rescue => e
        log_message("Error accessing current question: #{e.message}", :red)
        return
      end

      results = {}

      begin
        # For ordering quizzes or other special types, use the mini-game's evaluation method
        if current_question[:question_type] == 'ordering'
          # Convert the player_answers to the format expected by the mini-game's evaluate_answers
          mini_game_answers = {}
          @player_answers.each do |player_name, answer_data|
            next unless player_name && answer_data # Skip nil entries

            mini_game_answers[player_name] = {
              answer: answer_data[:answer],
              time_taken: answer_data[:time_taken] || 20
            }
          end

          # Call the mini-game's evaluate_answers method with error handling
          begin
            results = @current_mini_game.evaluate_answers(current_question, mini_game_answers) || {}
          rescue => e
            log_message("Error in mini-game evaluate_answers: #{e.message}", :red)
            # Create fallback results
            results = {}
            @player_answers.each do |player_name, answer_data|
              next unless player_name

              results[player_name] = {
                answer: answer_data[:answer] || [],
                correct: false,
                points: 0,
                partial_score: "Error calculating score"
              }
            end
          end
        else
          # For regular quizzes, use our pre-calculated points
          results = {}
          @player_answers.each do |player_name, answer_data|
            next unless player_name && answer_data # Skip nil entries

            results[player_name] = {
              answer: answer_data[:answer] || "No answer",
              correct: answer_data[:correct] || false,
              points: answer_data[:points] || 0
            }
          end
        end

        # Verify that results have required fields
        results.each do |player_name, result|
          # Ensure each result has the required fields with fallback values
          results[player_name][:answer] = result[:answer] || "No answer"
          results[player_name][:correct] = !!result[:correct] # Convert to boolean
          results[player_name][:points] = result[:points] || 0
        end

        # Update scores
        results.each do |player, result|
          @scores[player] = (@scores[player] || 0) + (result[:points] || 0)
        end
      rescue => e
        log_message("Error evaluating answers: #{e.message}", :red)
      end

      # Send results to all players - with error handling
      begin
        # Ensure we have valid data to broadcast
        safe_results = {}
        results.each do |player, result|
          safe_results[player] = {
            answer: result[:answer] || "No answer",
            correct: !!result[:correct], # Convert to boolean
            points: result[:points] || 0,
            partial_score: result[:partial_score] || ""
          }
        end

        # Sort scores safely
        safe_scores = {}
        begin
          safe_scores = @scores.sort_by { |_, score| -(score || 0) }.to_h
        rescue => e
          log_message("Error sorting scores: #{e.message}", :red)
          safe_scores = @scores.dup # Use unsorted if sorting fails
        end

        # For ordering questions, format the correct_answer as a list with numbers
        formatted_correct_answer = current_question[:correct_answer] || []
        if current_question[:question_type] == 'ordering'
          formatted_correct_answer = current_question[:correct_answer].map.with_index do |item, idx|
            "#{idx + 1}. #{item}" # Add numbers for easier reading
          end
        end

        broadcast_message({
          type: MessageType::ROUND_RESULT,
          question: current_question,
          results: safe_results,
          correct_answer: formatted_correct_answer,
          scores: safe_scores
        })
      rescue => e
        log_message("Error broadcasting results: #{e.message}", :red)
      end

      # Log current scores for the host - with error handling
      begin
        log_message("Current scores:", :cyan)

        # Safety check for scores
        if @scores.nil? || @scores.empty?
          log_message("No scores available", :yellow)
        else
          # Sort scores safely
          begin
            sorted_scores = @scores.sort_by { |_, score| -(score || 0) }
          rescue => e
            log_message("Error sorting scores for display: #{e.message}", :red)
            sorted_scores = @scores.to_a
          end

          # Display each score with error handling
          sorted_scores.each do |player_entry|
            # Extract player and score safely
            player = player_entry[0].to_s
            score = player_entry[1] || 0

            # Truncate player names if too long
            truncated_name = player.length > 15 ? "#{player[0...12]}..." : player
            log_message("#{truncated_name}: #{score} points", :light_blue)
          end
        end
      rescue => e
        log_message("Error displaying scores: #{e.message}", :red)
      end

      # Move to next question or round
      @current_question_index += 1
      @player_answers = {}
      @question_already_evaluated = false

      if @current_question_index >= @round_questions.size
        # End of round
        EM.add_timer(GitGameShow::DEFAULT_CONFIG[:transition_delay]) do
          start_next_round
        end
      else
        # Next question - use mini-game specific timing if available
        display_time = @current_mini_game.class.respond_to?(:question_display_time) ?
                    @current_mini_game.class.question_display_time :
                    GitGameShow::DEFAULT_CONFIG[:question_display_time]

        log_message("Next question in #{display_time} seconds...", :cyan)
        EM.add_timer(display_time) do
          ask_next_question
        end
      end
    end

    def start_game
      # If players are in an ended state, reset them first
      if @game_state == :ended
        log_message("Resetting players from previous game...", :light_black)
        begin
          broadcast_message({
            type: MessageType::GAME_RESET,
            message: "Get ready! The host is starting a new game..."
          })
          # Give players a moment to see the reset message
          sleep(1)
        rescue => e
          log_message("Error sending reset message: #{e.message}", :red)
        end
      end

      # Only start if we're in lobby state (which includes after reset)
      return unless @game_state == :lobby
      return if @players.empty?

      @game_state = :playing
      @current_round = 0

      # Reset the mini-game tracking for a new game
      @used_mini_games = []
      @available_mini_games = []

      broadcast_message({
        type: MessageType::GAME_START,
        rounds: @rounds,
        players: @players.keys
      })

      log_message("Game started with #{@players.size} players", :green)

      start_next_round
    end

    def start_next_round
      @current_round += 1

      # Reset question evaluation flag for the new round
      @question_already_evaluated = false

      # Check if we've completed all rounds
      if @current_round > @rounds
        log_message("All rounds completed! Showing final scores...", :green)
        EM.next_tick { end_game } # Use next_tick to ensure it runs after current operations
        return
      end

      # Select mini-game for this round with better variety
      @current_mini_game = select_next_mini_game.new
      @round_questions = @current_mini_game.generate_questions(@repo)
      @current_question_index = 0

      # Announce new round
      broadcast_message({
        type: 'round_start',
        round: @current_round,
        total_rounds: @rounds,
        mini_game: @current_mini_game.class.name,
        description: @current_mini_game.class.description
      })

      log_message("Starting round #{@current_round}: #{@current_mini_game.class.name}", :cyan)

      # Start the first question after a short delay
      EM.add_timer(3) do
        ask_next_question
      end
    end

    def ask_next_question
      return if @current_question_index >= @round_questions.size

      # Log information for debugging
      log_message("Preparing question #{@current_question_index + 1} of #{@round_questions.size}", :cyan)

      # Reset the evaluation flag for the new question
      @question_already_evaluated = false

      # Save current question without printing it to console
      current_question = @round_questions[@current_question_index]
      @current_question_id = "#{@current_round}-#{@current_question_index}"
      @question_start_time = Time.now
      @player_answers = {}

      # Send question to all players
      # Use mini-game specific timeout if available, otherwise use default
      # Ensure timeout is a number
      timeout = 0
      begin
        if @current_mini_game.class.respond_to?(:question_timeout)
          timeout = @current_mini_game.class.question_timeout.to_i
        else
          timeout = (GitGameShow::DEFAULT_CONFIG[:question_timeout] || 20).to_i
        end
        # Make sure we have a positive timeout value
        timeout = 20 if timeout <= 0
      rescue => e
        log_message("Error getting timeout value: #{e.message}", :red)
        timeout = 20  # Default fallback
      end

      # Prepare question data with type safety
      begin
        question_data = {
          type: MessageType::QUESTION,
          question_id: @current_question_id.to_s,
          question: current_question[:question].to_s,
          options: current_question[:options] || [],
          timeout: timeout,  # Now guaranteed to be a number
          round: @current_round.to_i,
          question_number: (@current_question_index + 1).to_i,
          total_questions: @round_questions.size.to_i
        }
      rescue => e
        log_message("Error preparing question data: #{e.message}", :red)
        # Create a minimal fallback question if something went wrong
        question_data = {
          type: MessageType::QUESTION,
          question_id: "#{@current_round}-#{@current_question_index}",
          question: "Question #{@current_question_index + 1}",
          options: ["Option 1", "Option 2", "Option 3", "Option 4"],
          timeout: 20,
          round: @current_round.to_i,
          question_number: (@current_question_index + 1).to_i,
          total_questions: @round_questions.size.to_i
        }
      end

      # Add additional question data safely
      begin
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
      rescue => e
        log_message("Error adding additional question data: #{e.message}", :red)
        # Continue without the additional data
      end

      # Don't log detailed question info to prevent author lists from showing
      log_message("Question #{@current_question_index + 1}/#{@round_questions.size}", :cyan)

      log_message("Broadcasting question to players...", :cyan)
      broadcast_message(question_data)

      # Set a timer for question timeout - ALWAYS evaluate after timeout
      # Use same timeout value we sent to clients (already guaranteed to be a number)
      EM.add_timer(timeout) do
        log_message("Question timeout (#{timeout}s) - evaluating", :yellow)
        evaluate_answers unless @current_question_index >= @round_questions.size
      end
    end

    def broadcast_scoreboard
      begin
        # Create a safe copy of scores
        safe_scores = {}
        if @scores && !@scores.empty?
          @scores.each do |player, score|
            next unless player && player.to_s != ""
            safe_scores[player.to_s] = score.to_i
          end
        end

        # Sort scores safely
        sorted_scores = {}
        begin
          sorted_scores = safe_scores.sort_by { |_, score| -(score || 0) }.to_h
        rescue => e
          log_message("Error sorting scores for scoreboard: #{e.message}", :red)
          sorted_scores = safe_scores  # Use unsorted if sorting fails
        end

        broadcast_message({
          type: MessageType::SCOREBOARD,
          scores: sorted_scores
        })
      rescue => e
        log_message("Error broadcasting scoreboard: #{e.message}", :red)
      end
    end

    def end_game
      @game_state = :ended

      # Initialize winner variable outside the begin block so it's visible throughout the method
      winner = nil

      # Wrap the main logic in a begin/rescue block
      begin
        # Safety check - make sure we have scores and they're not nil
        if @scores.nil? || @scores.empty?
          log_message("Game ended, but no scores were recorded.", :yellow)

          # Reset game state for potential restart
          @current_round = 0
          @game_state = :lobby
          @current_mini_game = nil
          @round_questions = []
          @current_question_index = 0
          @question_already_evaluated = false
          @player_answers = {}
          @scores = {}

          # Update UI
          update_player_list
          log_message("Ready for a new game! Type 'start' when players have joined.", :green)
          return
        end

        # Create a safe copy of scores to work with
        safe_scores = {}
        @scores.each do |player, score|
          next unless player && player != ""
          safe_scores[player] = score || 0
        end

        # Determine the winner with safety checks
        begin
          winner = safe_scores.max_by { |_, score| score || 0 }
        rescue => e
          log_message("Error determining winner: #{e.message}", :red)
        end

        # Safety check - ensure winner isn't nil and has valid data
        if winner.nil? || winner[0].nil? || winner[1].nil?
          log_message("Error: Could not determine winner. No valid scores found.", :red)

          # Create a synthetic winner as a fallback
          if !safe_scores.empty?
            # Take the first player as a last resort
            player_name = safe_scores.keys.first.to_s
            player_score = safe_scores.values.first || 0
            winner = [player_name, player_score]
            log_message("Using fallback winner: #{player_name}", :yellow)
          else
            # Reset and return early if we truly have no scores
            @scores = {}
            @current_round = 0
            @game_state = :lobby
            update_player_list
            return
          end
        end

        # Sort scores safely
        sorted_scores = {}
        begin
          sorted_scores = safe_scores.sort_by { |_, score| -(score || 0) }.to_h
        rescue => e
          log_message("Error sorting scores: #{e.message}", :red)
          sorted_scores = safe_scores # Use unsorted if sorting fails
        end

        # Notify all players
        begin
          broadcast_message({
            type: MessageType::GAME_END,
            winner: winner[0].to_s,
            scores: sorted_scores
          })
        rescue => e
          log_message("Error broadcasting final results: #{e.message}", :red)
        end
      rescue => e
        # Catch-all for any unhandled exceptions
        log_message("Critical error in end_game: #{e.message}", :red)
        # Still try to reset game state
        @game_state = :lobby
        @scores = {}
        @current_round = 0
      end

      # Display the final results on screen - with safety check
      if winner && winner[0] && winner[1]
        display_final_results(winner)
      else
        log_message("No valid winner data to display final results", :red)
      end

      # Reset game state for potential restart
      @scores = {}
      @current_round = 0
      @game_state = :lobby
      @current_mini_game = nil
      @round_questions = []
      @current_question_index = 0
      @question_already_evaluated = false
      @player_answers = {}

      # Re-initialize player scores for existing players
      @players.keys.each do |player_name|
        @scores[player_name] = 0
      end

      # Don't reset players yet - let them stay on the leaderboard screen
      # They'll be reset when a new game starts
      log_message("Players will remain on the leaderboard screen until a new game starts", :light_black)

      # Update UI
      update_player_list
      log_message("Game ended! Type 'start' to play again or 'exit' to quit.", :cyan)
    end

    def display_final_results(winner)
      begin
        # Safety check - make sure we have a main_width value
        main_width = @main_width || 80

        # Use log messages instead of clearing screen
        divider = "=" * (main_width - 5)
        log_message(divider, :yellow)
        log_message("🏆 GAME OVER - FINAL SCORES 🏆", :yellow)

        # Safety check for winner - we already checked in end_game but double-check here
        if !winner || !winner[0] || !winner[1]
          log_message("Error: Invalid winner data", :red)
          log_message("Ready for a new game! Type 'start' when players have joined.", :green)
          return
        end

        # Announce winner with defensive processing
        begin
          winner_name = winner[0].to_s
          winner_name = winner_name.length > 20 ? "#{winner_name[0...17]}..." : winner_name
          winner_score = winner[1].to_i
          log_message("Winner: #{winner_name} with #{winner_score} points!", :green)
        rescue => e
          log_message("Error displaying winner: #{e.message}", :red)
          log_message("A winner was determined but couldn't be displayed", :yellow)
        end

        # Create a safe copy of scores to work with
        safe_scores = {}
        begin
          if @scores && !@scores.empty?
            @scores.each do |player, score|
              next unless player && player.to_s != ""
              safe_scores[player.to_s] = score.to_i
            end
          end
        rescue => e
          log_message("Error copying scores: #{e.message}", :red)
        end

        # Safety check for scores
        if safe_scores.empty?
          log_message("No scores available to display", :yellow)
          log_message(divider, :yellow)
          log_message("Ready for a new game! Type 'start' when players have joined.", :green)
          return
        end

        # List players in console (but limit to avoid taking too much space)
        log_message("Leaderboard:", :cyan)

        leaderboard_entries = []

        # Sort scores safely
        sorted_scores = []
        begin
          sorted_scores = safe_scores.sort_by { |_, score| -(score || 0) }.to_a
        rescue => e
          log_message("Error sorting scores for display: #{e.message}", :red)
          sorted_scores = safe_scores.to_a
        end

        max_to_show = 10

        # Show limited entries in console with extra safety checks
        begin
          # Ensure we don't try to take more entries than exist
          entries_to_show = [sorted_scores.size, max_to_show].min

          sorted_scores.take(entries_to_show).each_with_index do |score_entry, index|
            # Extra safety check for each entry
            next unless score_entry && score_entry.is_a?(Array) && score_entry.size >= 2

            name = score_entry[0]
            score = score_entry[1]

            # Safely handle name and score
            player_name = name.to_s
            player_score = score.to_i

            # Truncate name if needed
            display_name = player_name.length > 15 ? "#{player_name[0...12]}..." : player_name

            # Format based on position
            case index
            when 0
              log_message("🥇 #{display_name}: #{player_score} points", :yellow)
            when 1
              log_message("🥈 #{display_name}: #{player_score} points", :light_blue)
            when 2
              log_message("🥉 #{display_name}: #{player_score} points", :light_magenta)
            else
              log_message("#{(index + 1).to_s}. #{display_name}: #{player_score} points", :white)
            end
          end
        rescue => e
          log_message("Error displaying leaderboard entries: #{e.message}", :red)
        end

        # If there are more players than shown, add a note
        if sorted_scores.size > max_to_show
          log_message("... and #{sorted_scores.size - max_to_show} more (see full results in file)", :light_black)
        end

        # Build complete entries array for file with safety checks
        begin
          sorted_scores.each_with_index do |score_entry, index|
            # Skip invalid entries
            next unless score_entry && score_entry.is_a?(Array) && score_entry.size >= 2

            # Use safe values
            player_name = score_entry[0].to_s
            player_score = score_entry[1].to_i

            # Add medals for file format
            medal = case index
                    when 0 then "🥇"
                    when 1 then "🥈"
                    when 2 then "🥉"
                    else "#{index + 1}."
                    end

            leaderboard_entries << "#{medal} #{player_name}: #{player_score} points"
          end
        rescue => e
          log_message("Error preparing leaderboard entries for file: #{e.message}", :red)
        end

        # Only try to save file if we have entries
        filename = nil
        if !leaderboard_entries.empty? && winner
          filename = save_leaderboard_to_file(winner, leaderboard_entries)
        end

        log_message(divider, :yellow)
        if filename
          log_message("Leaderboard saved to: #{filename}", :cyan)
        else
          log_message("No leaderboard file generated", :yellow)
        end
        log_message("Ready for a new game! Type 'start' when players have joined.", :green)
      rescue => e
        # Catch-all error handling
        log_message("Error displaying final results: #{e.message}", :red)
        log_message("Game has ended. Type 'start' for a new game or 'exit' to quit.", :yellow)
      end
    end

    def save_leaderboard_to_file(winner, leaderboard_entries)
      begin
        # Validate parameters with thorough checks
        if !winner || !winner.is_a?(Array) || winner.size < 2 || winner[0].nil? || winner[1].nil?
          log_message("Error: Invalid winner data for leaderboard file", :red)
          return nil
        end

        if !leaderboard_entries || !leaderboard_entries.is_a?(Array) || leaderboard_entries.empty?
          log_message("Error: Invalid entries data for leaderboard file", :red)
          return nil
        end

        # Create a unique filename with timestamp
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S") rescue "unknown_time"
        filename = "git_game_show_results_#{timestamp}.txt"

        # Use a base path that should be writable
        file_path = nil
        begin
          # First try current directory
          file_path = File.join(Dir.pwd, filename)

          # Test if we can write there
          unless File.writable?(Dir.pwd)
            # If not, try user's home directory
            file_path = File.join(Dir.home, filename)
            filename = File.join(Dir.home, filename) # Update filename to show full path
          end
        rescue => e
          log_message("Error with file path: #{e.message}", :red)
          # If all else fails, use /tmp (Unix) or %TEMP% (Windows)
          begin
            temp_dir = ENV['TEMP'] || ENV['TMP'] || '/tmp'
            file_path = File.join(temp_dir, filename)
            filename = file_path # Update filename to show full path
          rescue => e2
            log_message("Error setting up temp file path: #{e2.message}", :red)
            return nil
          end
        end

        # Make sure we have a valid file path
        unless file_path && !file_path.empty?
          log_message("Could not determine a valid file path for leaderboard", :red)
          return nil
        end

        # Get repo name from git directory path safely
        repo_name = "Unknown"
        begin
          if @repo && @repo.respond_to?(:dir) && @repo.dir && @repo.dir.respond_to?(:path)
            path = @repo.dir.path
            repo_name = path ? File.basename(path) : "Unknown"
          end
        rescue => e
          log_message("Error getting repo name: #{e.message}", :yellow)
        end

        # Get player count safely
        player_count = 0
        begin
          player_count = @players && @players.respond_to?(:keys) ? @players.keys.size : 0
        rescue => e
          log_message("Error getting player count: #{e.message}", :yellow)
        end

        # Extract winner data safely
        winner_name = "Unknown"
        winner_score = 0
        begin
          winner_name = winner[0].to_s
          winner_score = winner[1].to_i
        rescue => e
          log_message("Error extracting winner data: #{e.message}", :yellow)
        end

        # Write the file with error handling
        begin
          File.open(file_path, "w") do |file|
            # Write header
            file.puts "Git Game Show - Final Results"
            file.puts "═════════════════════════════"
            file.puts "Date: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
            file.puts "Repository: #{repo_name}"
            file.puts "Players: #{player_count}"
            file.puts ""

            # Write winner
            file.puts "WINNER: #{winner_name} with #{winner_score} points!"
            file.puts ""

            # Write full leaderboard
            file.puts "Full Leaderboard:"
            file.puts "─────────────────"
            leaderboard_entries.each do |entry|
              file.puts entry.to_s
            rescue => e
              file.puts "Error with entry: #{e.message}"
            end

            # Write footer
            file.puts ""
            file.puts "Thanks for playing Git Game Show!"
          end

          return filename
        rescue => e
          log_message("Error writing leaderboard file: #{e.message}", :red)
          return nil
        end
      rescue => e
        log_message("Error saving leaderboard: #{e.message}", :red)
        return nil
      end
    end

    # Removed old full-screen methods as we now use log_message based approach

    def broadcast_message(message, exclude: nil)
      return if message.nil?

      begin
        # Convert message to JSON safely
        json_message = nil
        begin
          json_message = message.to_json
        rescue => e
          log_message("Error converting message to JSON: #{e.message}", :red)

          # Try to simplify the message to make it JSON-compatible
          simplified_message = {
            type: message[:type] || "unknown",
            message: "Error processing full message"
          }
          json_message = simplified_message.to_json
        end

        return unless json_message

        # Send to each player with error handling
        @players.each do |player_name, ws|
          # Skip excluded player if specified
          next if exclude && player_name == exclude

          # Skip nil websockets
          next unless ws

          # Send with error handling for each individual player
          begin
            ws.send(json_message)
          rescue => e
            log_message("Error sending to #{player_name}: #{e.message}", :yellow)
            # We don't remove the player here, as they might just have temporary connection issues
          end
        end
      rescue => e
        log_message("Fatal error in broadcast_message: #{e.message}", :red)
      end
    end

    def setup_console_commands
      Thread.new do
        prompt = TTY::Prompt.new

        loop do
          command = prompt.select("Host commands:", {
            "Start game" => :start,
            "Show players" => :players,
            "Show scoreboard" => :scoreboard,
            "End game" => :end,
            "Exit server" => :exit
          })

          case command
          when :start
            if @players.size < 1
              puts "Need at least one player to start".colorize(:red)
            else
              start_game
            end
          when :players
            puts "Connected players:".colorize(:cyan)
            @players.keys.each { |name| puts "- #{name}" }
          when :scoreboard
            puts "Current scores:".colorize(:cyan)
            @scores.sort_by { |_, score| -score }.each do |name, score|
              puts "- #{name}: #{score}"
            end
          when :end
            puts "Ending game...".colorize(:yellow)
            end_game
          when :exit
            puts "Shutting down server...".colorize(:yellow)
            EM.stop_event_loop
            break
          end
        end
      end
    end

    def setup_fixed_console_commands
      # Log initial instructions
      log_message("Available commands: help, start, exit", :cyan)
      log_message("Type a command and press Enter", :cyan)

      # Show that the server is ready
      log_message("Server is running. Waiting for players to join...", :green)

      # Handle commands in a separate thread
      Thread.new do
        loop do
          # Show command prompt and get input
          draw_command_prompt
          command = gets&.chomp&.downcase
          next unless command

          # Process commands
          case command
          when 'start'
            if @players.empty?
              log_message("Need at least one player to start", :red)
            else
              log_message("Starting game with #{@players.size} players...", :green)
              start_game
            end
          # 'players' command removed - player list is always visible in sidebar
          when 'help'
            log_message("Available commands:", :cyan)
            log_message("  start   - Start the game with current players", :cyan)
            log_message("  end     - End current game and show final scores", :cyan)
            log_message("  reset   - Manually reset players to waiting room (after game ends)", :cyan)
            log_message("  help    - Show this help message", :cyan)
            log_message("  exit    - Shut down the server and exit", :cyan)
          when 'end'
            if @game_state == :playing
              log_message("Ending game early...", :yellow)
              end_game
            elsif @game_state == :ended
              log_message("Game already ended. Type 'start' to begin a new game.", :yellow)
            else
              log_message("No game in progress to end", :yellow)
            end
          when 'reset'
            # Add a separate reset command for manually resetting players
            if @game_state == :ended
              log_message("Manually resetting all players to waiting room state...", :yellow)

              # Send a game reset message to all players
              broadcast_message({
                type: MessageType::GAME_RESET,
                message: "Game has been reset by the host. Waiting for a new game to start."
              })

              # Update game state
              @game_state = :lobby
            else
              log_message("Can only reset after a game has ended", :yellow)
            end
          when 'exit'
            # Clean up before exiting
            log_message("Shutting down server...", :yellow)
            print @cursor.show  # Make sure cursor is visible
            print @cursor.clear_screen
            EM.stop_event_loop
            break
          else
            log_message("Unknown command: #{command}. Type 'help' for available commands.", :red)
          end

          # Small delay to process any display changes
          sleep 0.1
        end
      end
    end

    def print_players_list
      puts "\nCurrent players:"
      if @players.empty?
        puts "No players have joined yet".colorize(:yellow)
      else
        @players.keys.each_with_index do |name, i|
          puts "#{i+1}. #{name}"
        end
      end
    end

    def refresh_host_ui
      # Only clear the screen for the first draw
      if !@ui_drawn
        system("clear") || system("cls")

        display_welcome_banner

        puts "\n             Server Started - Port: #{port}\n".colorize(:light_blue).center(80)

        @ui_drawn = true
      else
        # Just print a separator for subsequent updates
        puts "\n\n" + ("═" * 60)
        puts "Git Game Show - Status Update".center(60).colorize(:green)
        puts ("═" * 60)
      end

      # Server info
      puts "\n════════════════════ Server Info ════════════════════".colorize(:cyan)
      puts "Status: #{game_state_text}".colorize(game_state_color)
      puts "Rounds: #{@current_round}/#{rounds}".colorize(:light_blue)
      puts "Repository: #{repo.dir.path}".colorize(:light_blue)

      # Display join link prominently
      puts "\n════════════════════ Join Link ═════════════════════".colorize(:green)
      puts @join_link.to_s.colorize(:yellow)

      # Player list
      puts "\n════════════════════ Players ═══════════════════════".colorize(:cyan)
      if @players.empty?
        puts "No players have joined yet".colorize(:yellow)
      else
        @players.keys.each_with_index do |name, i|
          puts "#{i+1}. #{name}"
        end
      end

      # Current game state info
      case @game_state
      when :lobby
        puts "\nWaiting for players to join. Type 'start' when ready.".colorize(:yellow)
        puts "Players can join using the link above.".colorize(:yellow)
        puts "Type 'players' to see the current list of players.".colorize(:yellow)
      when :playing
        puts "\n════════════════════ Game Info ═══════════════════════".colorize(:cyan)
        puts "Current round: #{@current_round}/#{rounds}".colorize(:light_blue)
        puts "Current mini-game: #{@current_mini_game&.class&.name || 'N/A'}".colorize(:light_blue)
        puts "Question: #{@current_question_index + 1}/#{@round_questions.size}".colorize(:light_blue) if @round_questions&.any?

        # Show scoreboard
        puts "\n═══════════════════ Scoreboard ══════════════════════".colorize(:cyan)
        if @scores.empty?
          puts "No scores yet".colorize(:yellow)
        else
          @scores.sort_by { |_, score| -score }.each_with_index do |(name, score), i|
            case i
            when 0
              puts "🥇 #{name}: #{score} points".colorize(:light_yellow)
            when 1
              puts "🥈 #{name}: #{score} points".colorize(:light_blue)
            when 2
              puts "🥉 #{name}: #{score} points".colorize(:light_magenta)
            else
              puts "#{i+1}. #{name}: #{score} points"
            end
          end
        end
      when :ended
        puts "\nGame has ended. Type 'exit' to quit or 'start' to begin a new game.".colorize(:green)
      end


      # Only print command help on first draw to avoid cluttering output
      if !@ui_drawn
        puts "\nAvailable commands: help, start, players, status, end, exit".colorize(:light_black)
        puts "Type a command and press Enter".colorize(:light_black)
      end
    end

    def print_help_message
      puts ""
      puts "═══════════════════ Help ═════════════════════════"
      puts "Available commands:"
      puts "  help    - Show this help message"
      puts "  start   - Start the game with current players"
      puts "  players - Show list of connected players"
      puts "  status  - Refresh the status display"
      puts "  end     - End the current game"
      puts "  exit    - Shut down the server and exit"
      puts "══════════════════════════════════════════════════"
    end

    def print_status_message(message, status)
      color = case status
              when :success then :green
              when :error then :red
              when :warning then :yellow
              else :white
              end
      puts "\n> #{message}".colorize(color)
    end

    def game_state_text
      case @game_state
      when :lobby then "Waiting for players"
      when :playing then "Game in progress"
      when :ended then "Game over"
      end
    end

    def game_state_color
      case @game_state
      when :lobby then :yellow
      when :playing then :green
      when :ended then :light_blue
      end
    end

    # Select the next mini-game to ensure variety and avoid repetition
    def select_next_mini_game
      # Special case for when only one mini-game type is enabled
      if @mini_games.size == 1
        selected_game = @mini_games.first
        log_message("Only one mini-game type available: #{selected_game.name}", :light_black)
        return selected_game
      end

      # If we have no more available mini-games, reset the cycle
      if @available_mini_games.empty?
        # Handle the case where we might have only one game left after excluding the last used
        if @mini_games.size <= 2
          @available_mini_games = @mini_games.dup
        else
          # Repopulate with all mini-games except the last one used (if possible)
          @available_mini_games = @mini_games.reject { |game| game == @used_mini_games.last }
        end

        # Log that we're starting a new cycle
        log_message("Starting a new cycle of mini-games", :light_black)
      end

      # Select a random game from the available ones
      selected_game = @available_mini_games.sample
      return @mini_games.first if selected_game.nil? # Fallback for safety

      # Remove the selected game from available and add to used
      @available_mini_games.delete(selected_game)
      @used_mini_games << selected_game

      # Log which mini-game was selected
      log_message("Selected #{selected_game.name} for this round", :light_black)

      # Return the selected game class
      selected_game
    end

    def load_mini_games
      # Enable all mini-games
      [
        GitGameShow::AuthorQuiz,
        GitGameShow::CommitMessageQuiz,
        GitGameShow::CommitMessageCompletion,
        GitGameShow::DateOrderingQuiz
      ]
    end
  end
end
