require 'websocket-client-simple'
require 'securerandom'
require 'timeout'

module GitGameShow
  class PlayerClient
    attr_reader :host, :port, :password, :name, :secure

    def initialize(host:, port:, password:, name:, secure: false)
      @host = host
      @port = port
      @password = password
      @name = name
      @secure = secure
      @ws = nil
      @prompt = TTY::Prompt.new
      @players = []
      @game_state = :lobby  # :lobby, :playing, :ended
      @current_timer_id = nil
      @game_width = 80
    end

    def connect
      begin
        client = self # Store reference to the client instance

        # Check if the connection should use a secure protocol
        # For ngrok TCP tunnels, we should use regular ws:// since ngrok tcp doesn't provide SSL termination
        # Only use wss:// if the secure flag is explicitly set (for configured HTTPS endpoints)
        protocol = if @secure
          puts "Using secure WebSocket connection (wss://)".colorize(:light_blue)
          'wss'
        else
          'ws'
        end

        @ws = WebSocket::Client::Simple.connect("#{protocol}://#{host}:#{port}")

        @ws.on :open do
          puts "Connected to server".colorize(:green)
          # Use the stored client reference
          client.send_join_request
        end

        @ws.on :message do |msg|
          client.handle_message(msg)
        end

        @ws.on :error do |e|
          puts "Error: #{e.message}".colorize(:red)
        end

        @ws.on :close do |e|
          puts "Connection closed (#{e.code}: #{e.reason})".colorize(:yellow)
          exit(1)
        end

        # Keep the client running
        loop do
          sleep(1)

          # Check if connection is still alive
          if @ws.nil? || @ws.closed?
            puts "Connection lost. Exiting...".colorize(:red)
            exit(1)
          end
        end
      rescue => e
        puts "Failed to connect: #{e.message}".colorize(:red)
      end
    end

    # Make these methods public so they can be called from the WebSocket callbacks
    def send_join_request
      send_message({
        type: MessageType::JOIN_REQUEST,
        name: name,
        password: password
      })
    end

    # Make public for WebSocket callback
    def handle_message(msg)
      begin
        data = JSON.parse(msg.data)

        # Remove debug print to reduce console noise

        case data['type']
        when MessageType::JOIN_RESPONSE
          handle_join_response(data)
        when MessageType::GAME_START
          handle_game_start(data)
        when MessageType::GAME_RESET  # New handler for game reset
          handle_game_reset(data)
        when 'player_joined', 'player_left'
          handle_player_update(data)
        when 'round_start'
          handle_round_start(data)
        when MessageType::QUESTION
          handle_question(data)
        when MessageType::ROUND_RESULT
          handle_round_result(data)
        when MessageType::SCOREBOARD
          handle_scoreboard(data)
        when MessageType::GAME_END
          handle_game_end(data)
        when MessageType::ANSWER_FEEDBACK
          handle_answer_feedback(data)
        when MessageType::CHAT
          handle_chat(data)
        else
          puts "Unknown message type: #{data['type']}".colorize(:yellow)
        end
      rescue JSON::ParserError => e
        puts "Invalid message format: #{e.message}".colorize(:red)
      rescue => e
        puts "Error processing message: #{e.message}".colorize(:red)
      end
    end

    def handle_join_response(data)
      if data['success']
        @players = data['players'] # Get the full player list from server
        display_waiting_room
      else
        puts "Failed to join: #{data['message']}".colorize(:red)
        exit(1)
      end
    end

    def display_waiting_room
      clear_screen

      # Draw header with fancy box
      terminal_width = `tput cols`.to_i rescue @game_width
      terminal_height = `tput lines`.to_i rescue 24

      # Create title box
      puts "╭#{"─" * (terminal_width - 2)}╮".colorize(:green)
      puts "│#{" Git Game Show - Waiting Room ".center(terminal_width - 2)}│".colorize(:green)
      puts "╰#{"─" * (terminal_width - 2)}╯".colorize(:green)

      # Left column width (2/3 of terminal) for main content
      left_width = (terminal_width * 0.65).to_i

      # Display instructions and welcome information
      puts "\n"
      puts "  Welcome to Git Game Show!".colorize(:yellow)
      puts "  Test your knowledge about Git and your team's commits through fun mini-games.".colorize(:light_white)
      puts "\n"
      puts "  🔹 Instructions:".colorize(:light_blue)
      puts "    • The game consists of multiple rounds with different question types".colorize(:light_white)
      puts "    • Each round has a theme based on Git commit history".colorize(:light_white)
      puts "    • Answer questions as quickly as possible for maximum points".colorize(:light_white)
      puts "    • The player with the most points at the end wins!".colorize(:light_white)
      puts "\n"
      puts "  🔹 Status: Waiting for the host to start the game...".colorize(:light_yellow)
      puts "\n"

      # Draw player section in a box
      player_box_width = terminal_width - 4
      puts ("╭#{"─" * player_box_width}╮").center(terminal_width).colorize(:light_blue)
      puts ("│#{" Players ".center(player_box_width)}│").center(terminal_width).colorize(:light_blue)
      puts ("╰#{"─" * player_box_width}╯").center(terminal_width).colorize(:light_blue)

      # Display list of players in a nicer format
      if @players.empty?
        puts "  (No other players yet)".colorize(:light_black)
      else
        # Calculate number of columns based on terminal width and name lengths
        max_name_length = @players.map(&:length).max + 10 # Extra space for number and "(You)" text

        # Add more spacing between players - increase padding from 4 to 10
        column_width = max_name_length + 12  # More generous spacing
        num_cols = [terminal_width / column_width, 3].min # Cap at 3 columns max
        num_cols = 1 if num_cols < 1

        # Use fewer columns for better spacing
        if num_cols > 1 && @players.size > 6
          # If we have many players, prefer fewer columns with more space
          num_cols = [num_cols, 2].min
        end

        # Split players into rows for multi-column display
        player_rows = @players.each_slice(((@players.size + num_cols - 1) / num_cols).ceil).to_a

        puts "\n"
        player_rows.each do |row_players|
          row_str = "  "
          row_players.each_with_index do |player, idx|
            col_idx = player_rows.index { |rp| rp.include?(player) }
            player_num = col_idx * player_rows[0].length + idx + 1

            # Apply different color for current player
            if player == @name
              row_str += "#{player_num}. #{player} (You)".colorize(:green).ljust(column_width)
            else
              row_str += "#{player_num}. #{player}".colorize(:light_blue).ljust(column_width)
            end
          end
          # Add a blank line between rows for vertical spacing too
          puts row_str
          puts ""
        end
      end

      puts "\n"
      puts "  When the game starts, you'll see questions appear automatically.".colorize(:light_black)
      puts "  Get ready to test your Git knowledge!".colorize(:light_yellow)
      puts "\n"
    end

    def clear_screen
      # Reset cursor and clear entire screen
      print "\033[H\033[2J"  # Move to home position and clear screen
      print "\033[3J"        # Clear scrollback buffer

      # Reserve bottom line for timer status
      term_height = `tput lines`.to_i rescue 24

      # Move to bottom of screen and clear status line
      print "\e[#{term_height};1H"
      print "\e[K"
      print "\e[H"  # Move cursor back to home position

      STDOUT.flush
    end


    # Helper method to print a countdown timer status in the window title
    # This doesn't interfere with the terminal content
    def update_title_timer(seconds)
      # Use terminal escape sequence to update window title
      # This is widely supported and doesn't interfere with content
      print "\033]0;Git Game Show - #{seconds} seconds remaining\007"
      STDOUT.flush
    end

    # Super simple ordering implementation with minimal screen updates
    def handle_ordering_question(options, question_text = nil)
      # Create a copy of the options that we can modify
      current_order = options.dup
      cursor_index = 0
      selected_index = nil
      num_options = current_order.size
      question_text ||= "Put these commits in chronological order (oldest to newest)"

      # Extract question data if available
      data = Thread.current[:question_data] || {}
      question_number = data['question_number']
      total_questions = data['total_questions']

      # Draw the initial screen once
      # system('clear') || system('cls')

      # Draw question header once
      if question_number && total_questions
        box_width = 42
        puts ""
        puts ("╭" + "─" * box_width + "╮").center(@game_width).colorize(:light_blue)
        puts ("│#{'Question #{question_number} of #{total_questions}'.center(box_width-2)}│").center(@game_width).colorize(:light_blue)
        puts ("╰" + "─" * box_width + "╯").center(@game_width).colorize(:light_blue)
      end

      # Draw the main question text once
      puts "\n   #{question_text}".colorize(:light_blue)
      puts "   Put in order from oldest (1) to newest (#{num_options})".colorize(:light_blue)

      # Draw instructions once
      puts "\n   INSTRUCTIONS:".colorize(:yellow)
      puts "   • Use ↑/↓ arrows to move cursor".colorize(:white)
      puts "   • Press ENTER to select/deselect an item to move".colorize(:white)
      puts "   • Selected items move with cursor when you press ↑/↓".colorize(:white)
      puts "   • Navigate to Submit and press ENTER when finished".colorize(:white)

      # Calculate where the list content starts on screen
      content_start_line = question_number ? 15 : 12

      # Draw the list content (this will be redrawn repeatedly)
      draw_ordering_list(current_order, cursor_index, selected_index, content_start_line, num_options)

      # Main interaction loop
      loop do
        # Read a single keypress
        char = read_char

        # Clear any message on this line
        move_cursor_to(content_start_line + num_options + 2, 0)
        print "\r\033[K"

        # Check if the timer has expired
        if @timer_expired
          # If timer expired, just return the current ordering
          return current_order
        end

        # Now char is an integer (ASCII code)
        case char
        when 13, 10  # Enter key (CR or LF)
          if cursor_index == num_options
            # Submit the answer
            # Move to end of list and print a message
            move_cursor_to(content_start_line + num_options + 3, 0)
            print "\r\033[K"
            print "   Submitting your answer...".colorize(:green)
            return current_order
          elsif selected_index == cursor_index
            # Deselect the currently selected item
            selected_index = nil
          else
            # Select the item at cursor position
            selected_index = cursor_index
          end
        when 65, 107, 119  # Up arrow (65='A'), k (107), w (119)
          # Move cursor up
          if selected_index == cursor_index && cursor_index > 0
            # Move the selected item up in the order
            current_order[cursor_index], current_order[cursor_index - 1] =
              current_order[cursor_index - 1], current_order[cursor_index]
            cursor_index -= 1
            selected_index = cursor_index
          elsif cursor_index > 0
            # Just move the cursor up
            cursor_index -= 1
          end
        when 66, 106, 115  # Down arrow (66='B'), j (106), s (115)
          if selected_index == cursor_index && cursor_index < num_options - 1
            # Move the selected item down in the order
            current_order[cursor_index], current_order[cursor_index + 1] =
              current_order[cursor_index + 1], current_order[cursor_index]
            cursor_index += 1
            selected_index = cursor_index
          elsif cursor_index < num_options
            # Just move the cursor down
            cursor_index += 1
          end
        end

        # Redraw just the list portion of the screen
        draw_ordering_list(current_order, cursor_index, selected_index, content_start_line, num_options)
      end
    end

    # Helper method to draw just the list portion of the ordering UI
    def draw_ordering_list(items, cursor_index, selected_index, start_line, num_options)
      # Clear the line above the list (was used for debugging)
      debug_line = start_line - 1
      move_cursor_to(debug_line, 0)
      print "\r\033[K"  # Clear debug line

      # Move cursor to the start position for the list
      move_cursor_to(start_line, 0)

      # Clear all lines that will contain list items and the submit button
      (num_options + 2).times do |i|
        move_cursor_to(start_line + i, 0)
        print "\r\033[K"  # Clear current line without moving cursor
      end

      # Draw each item with appropriate highlighting
      items.each_with_index do |item, idx|
        # Calculate the line for this item
        item_line = start_line + idx
        move_cursor_to(item_line, 0)

        if selected_index == idx
          # Selected item (being moved)
          print "   → #{idx + 1}. #{item}".colorize(:light_green)
        elsif cursor_index == idx
          # Cursor is on this item
          print "   → #{idx + 1}. #{item}".colorize(:light_blue)
        else
          # Normal item
          print "     #{idx + 1}. #{item}".colorize(:white)
        end
      end

      # Add the Submit option at the bottom
      move_cursor_to(start_line + num_options, 0)
      if cursor_index == num_options
        print "   → Submit Answer".colorize(:yellow)
      else
        print "     Submit Answer".colorize(:white)
      end

      # Move cursor after the list
      move_cursor_to(start_line + num_options + 1, 0)

      # Ensure output is visible
      STDOUT.flush
    end

    # Helper to position cursor at a specific row/column
    def move_cursor_to(row, col)
      print "\033[#{row};#{col}H"
    end

    # Simplified key input reader that uses numbers for arrow keys
    def read_char
      begin
        system("stty raw -echo")

        # Read a character
        c = STDIN.getc

        # Special handling for escape sequences
        if c == "\e"
          # Could be an arrow key - read more
          begin
            # Check if there's more data to read
            if IO.select([STDIN], [], [], 0.1)
              c2 = STDIN.getc
              if c2 == "["
                # This is an arrow key or similar control sequence
                if IO.select([STDIN], [], [], 0.1)
                  c3 = STDIN.getc
                  case c3
                  when 'A' then return 65  # Up arrow (ASCII 'A')
                  when 'B' then return 66  # Down arrow (ASCII 'B')
                  when 'C' then return 67  # Right arrow
                  when 'D' then return 68  # Left arrow
                  else
                    return c3.ord  # Other control character
                  end
                end
              else
                return c2.ord  # ESC followed by another key
              end
            end
          rescue => e
            # Just return ESC if there's an error
            return 27  # ESC key
          end
        end

        # Just return the ASCII value for the key
        return c.ord
      ensure
        system("stty -raw echo")
      end
    end

    # Non-blocking key input reader that supports timeouts
    def read_char_with_timeout
      begin
        # Check if there's input data available
        if IO.select([STDIN], [], [], 0.1)
          # Read a character
          c = STDIN.getc

          # Handle nil case (EOF)
          return nil if c.nil?

          # Special handling for escape sequences
          if c == "\e"
            # Could be an arrow key - read more
            begin
              # Check if there's more data to read
              if IO.select([STDIN], [], [], 0.1)
                c2 = STDIN.getc
                if c2 == "["
                  # This is an arrow key or similar control sequence
                  if IO.select([STDIN], [], [], 0.1)
                    c3 = STDIN.getc
                    case c3
                    when 'A' then return 65  # Up arrow (ASCII 'A')
                    when 'B' then return 66  # Down arrow (ASCII 'B')
                    when 'C' then return 67  # Right arrow
                    when 'D' then return 68  # Left arrow
                    else
                      return c3.ord  # Other control character
                    end
                  end
                else
                  return c2.ord  # ESC followed by another key
                end
              end
            rescue => e
              # Just return ESC if there's an error
              return 27  # ESC key
            end
          end

          # Just return the ASCII value for the key
          return c.ord
        end

        # No input available - return nil for timeout
        return nil
      rescue => e
        # In case of error, return nil
        return nil
      end
    end

    # Helper method to display countdown using a status bar at the bottom of the screen
    def update_countdown_display(seconds, original_seconds)
      # Get terminal dimensions
      term_height = `tput lines`.to_i rescue 24

      # Calculate a simple progress bar
      total_width = 30
      progress_width = ((seconds.to_f / original_seconds) * total_width).to_i
      remaining_width = total_width - progress_width

      # Choose color based on time remaining
      color = if seconds <= 5
                :red
              elsif seconds <= 10
                :light_yellow
              else
                :green
              end

      # Create status bar with progress indicator
      bar = "[#{"█" * progress_width}#{" " * remaining_width}]"
      status_text = " ⏱️  Time remaining: #{seconds.to_s.rjust(2)} seconds ".colorize(color) + bar

      # Save cursor position
      print "\e7"

      # Move to bottom of screen (status line)
      print "\e[#{term_height};1H"

      # Clear the line
      print "\e[K"

      # Print status bar at bottom of screen
      print status_text

      # Restore cursor position
      print "\e8"
      STDOUT.flush
    end

    def handle_game_start(data)
      @game_state = :playing
      @players = data['players']
      @total_rounds = data['rounds']

      clear_screen

      # Display a fun "Game Starting" animation
      box_width = 40
      puts "\n\n"
      puts ("╭" + "─" * box_width + "╮").center(@game_width).colorize(:green)
      puts ("│" + "Game starting...".center(box_width) + "│").center(@game_width).colorize(:green)
      puts ("╰" + "─" * box_width + "╯").center(@game_width).colorize(:green)
      puts "\n\n"

      puts "   Total rounds: #{@total_rounds}".colorize(:light_blue)
      puts "   Players: #{@players.join(', ')}".colorize(:light_blue)
      puts "\n\n"
      puts "   Get ready for the first round!".colorize(:yellow)
      puts "\n\n"
    end

    def handle_player_update(data)
      # Update the players list
      @players = data['players']

      if @game_state == :lobby
        # If we're in the lobby, refresh the waiting room UI with updated player list
        display_waiting_room

        # Show notification at the bottom
        if data['type'] == 'player_joined'
          puts "\n  🟢 #{data['name']} has joined the game".colorize(:green)
        else
          puts "\n  🔴 #{data['name']} has left the game".colorize(:yellow)
        end
      else
        # During gameplay, just show a notification without disrupting the game UI
        terminal_width = `tput cols`.to_i rescue @game_width

        # Create a notification box that won't interfere with ongoing gameplay
        puts ""
        puts "╭#{"─" * (terminal_width - 2)}╮".colorize(:light_blue)

        if data['type'] == 'player_joined'
          puts "│#{" 🟢 #{data['name']} has joined the game ".center(terminal_width - 2)}│".colorize(:green)
        else
          puts "│#{" 🔴 #{data['name']} has left the game ".center(terminal_width - 2)}│".colorize(:yellow)
        end

        # Don't show all players during gameplay - can be too disruptive
        # Just show the total count
        puts "│#{" Total players: #{data['players'].size} ".center(terminal_width - 2)}│".colorize(:light_blue)
        puts "╰#{"─" * (terminal_width - 2)}╯".colorize(:light_blue)
      end
    end

    def handle_round_start(data)
      clear_screen

      # Draw a fancy round header
      round_num = data['round']
      total_rounds = data['total_rounds']
      mini_game = data['mini_game']
      description = data['description']

      puts "\n\n"

      # Box is drawn with exactly 45 "━" characters for the top and bottom borders
      # The top and bottom including borders are 48 characters wide
      box_width = 42
      box_top    = ("╭" + "─" * (box_width - 2) + "╮").center(@game_width)
      box_bottom = ("╰" + "─" * (box_width - 2) + "╯").center(@game_width)
      box_middle = "│#{"Round #{round_num} of #{total_rounds}".center(box_width - 2)}│".center(@game_width)

      # Output the box
      puts box_top.colorize(:green)
      puts box_middle.colorize(:green)
      puts box_bottom.colorize(:green)
      puts "\n"
      puts "   Mini-game: #{mini_game}".colorize(:light_blue)
      puts "   #{description}".colorize(:light_blue)
      puts "\n"

      # Count down to the start - don't sleep here as we're waiting for the server
      # to send us the questions after a fixed delay
      puts "   Get ready for the first question...".colorize(:yellow)
      puts "   Questions will appear automatically when the game begins.".colorize(:yellow)
      puts "   The host is controlling the timing of all questions.".colorize(:light_blue)
      puts "\n\n"
    end

    def handle_question(data)
      # Invalidate any previous timer
      @current_timer_id = SecureRandom.uuid

      # Clear the screen completely
      clear_screen

      question_num = data['question_number']
      total_questions = data['total_questions']
      question = data['question']
      timeout = data['timeout']

      # Store question data in thread-local storage for access in other methods
      Thread.current[:question_data] = data

      # No need to reserve space for timer - it will be at the bottom of the screen

      # Display question header
      puts "\n"

      # Draw a simple box for the question header
      box_width = 42
      box_top    = ("╭" + "─" * (box_width - 2) + "╮").center(@game_width)
      box_bottom = ("╰" + "─" * (box_width - 2) + "╯").center(@game_width)
      box_middle = "│#{"Question #{question_num} of #{total_questions}".center(box_width - 2)}│".center(@game_width)

      # Output the question box
      puts box_top.colorize(:light_blue)
      puts box_middle.colorize(:light_blue)
      puts box_bottom.colorize(:light_blue)
      puts "\n"

      # Display question
      puts "   #{question}".colorize(:light_blue)

      # Display commit info if available
      if data['commit_info']
        puts "\n   Commit: #{data['commit_info']}".colorize(:yellow)
      end
      puts "\n"

      # Create a unique timer ID for this question
      timer_id = SecureRandom.uuid
      @current_timer_id = timer_id

      # Initialize remaining time for scoring
      @time_remaining = timeout

      # Update the timer display immediately
      update_countdown_display(timeout, timeout)

      # Variable to track if the timer has expired
      @timer_expired = false

      # Start countdown in a background thread with new approach
      countdown_thread = Thread.new do
        begin
          remaining = timeout

          while remaining > 0 && @current_timer_id == timer_id
            # Update both window title and fixed position display
            update_title_timer(remaining)
            update_countdown_display(remaining, timeout)

            # Sound alert when time is almost up (< 5 seconds)
            if remaining < 5 && remaining > 0
              print "\a" if remaining % 2 == 0 # Beep on even seconds
            end

            # Store time for scoring
            @time_remaining = remaining

            # Wait one second
            sleep 1
            remaining -= 1
          end

          # Final update when timer reaches zero
          if @current_timer_id == timer_id
            update_countdown_display(0, timeout)

            # IMPORTANT: Send a timeout answer when time expires
            # without waiting for user input
            @timer_expired = true

            # Clear the screen to break out of any prompt/UI state
            clear_screen

            puts "\n   ⏰ TIME'S UP! Timeout answer submitted.".colorize(:red)
            puts "   Waiting for the next question...".colorize(:yellow)

            # Force terminal back to normal mode in case something is waiting for input
            system("stty sane") rescue nil
            system("tput cnorm") rescue nil # Re-enable cursor

            # Send a timeout answer to the server
            send_message({
              type: MessageType::ANSWER,
              name: name,
              answer: nil, # nil indicates timeout
              question_id: data['question_id']
            })

            # Force kill other input methods by returning directly from handle_question
            # This breaks out of the entire method, bypassing any pending input operations
            return
          end
        rescue => e
          # Silent failure for robustness
        end
      end

      # Handle different question types - but wrap in a separate thread
      # so that timeouts can interrupt the UI
      input_thread = Thread.new do
        if data['question_type'] == 'ordering'
          # Special UI for ordering questions
          answer = handle_ordering_question(data['options'], data['question'])
        elsif data['options'] && !data['options'].empty?
          # Regular multiple choice question - with interrupt check
          begin
            # Configure prompt to be interruptible
            answer = @prompt.select("   Choose your answer:", data['options'], per_page: 10) do |menu|
              # Check for timeout periodically during menu interactions
              menu.help ""
              menu.default 1
            end
          rescue TTY::Reader::InputInterrupt
            # If interrupted, just return nil
            nil
          end
        else
          # Free text answer - with interrupt check
          begin
            answer = @prompt.ask("   Your answer:") do |q|
              # Check for timeout periodically
              q.help ""
            end
          rescue TTY::Reader::InputInterrupt
            # If interrupted, just return nil
            nil
          end
        end
      end

      # Wait for input but with timeout
      answer = nil
      begin
        # Try to join the thread but allow for interruption
        Timeout.timeout(timeout + 0.5) do
          answer = input_thread.value
        end
      rescue Timeout::Error
        # If timeout occurs during join, kill the thread
        input_thread.kill if input_thread.alive?
      end

      # Only send user answer if timer hasn't expired
      unless @timer_expired
        # Send answer back to server
        send_message({
          type: MessageType::ANSWER,
          name: name,
          answer: answer,
          question_id: data['question_id']
        })

        puts "\n   Answer submitted! Waiting for feedback...".colorize(:green)
      end

      # Stop the timer by invalidating its ID and terminating the thread
      @current_timer_id = SecureRandom.uuid  # Change timer ID to signal thread to stop
      countdown_thread.kill if countdown_thread.alive? # Force kill the thread

      # Reset window title
      print "\033]0;Git Game Show\007"

      # Clear the timer status line at bottom
      term_height = `tput lines`.to_i rescue 24
      print "\e7"              # Save cursor position
      print "\e[#{term_height};1H"  # Move to bottom line
      print "\e[K"             # Clear line
      print "\e8"              # Restore cursor position

      # The server will send ANSWER_FEEDBACK message right away, then we'll see feedback
    end

    # Handle immediate feedback after submitting an answer
    def handle_answer_feedback(data)
      # Invalidate any running timer and reset window title
      @current_timer_id = SecureRandom.uuid
      print "\033]0;Git Game Show\007"  # Reset window title

      # Clear the timer status line at bottom
      term_height = `tput lines`.to_i rescue 24
      print "\e7"              # Save cursor position
      print "\e[#{term_height};1H"  # Move to bottom line
      print "\e[K"             # Clear line
      print "\e8"              # Restore cursor position

      # Don't clear screen, just display the feedback under the question
      # This keeps the context of the question while showing the result

      # Add a visual separator
      puts "\n   #{"─" * 40}".colorize(:light_black)
      puts "\n"

      # Show immediate feedback
      if data['answer'] == "TIMEOUT"
        # Special handling for timeouts
        puts "   ⏰ TIME'S UP! You didn't answer in time.".colorize(:red)
        puts "   The correct answer was: #{data['correct_answer']}".colorize(:yellow)
        puts "   (0 points)".colorize(:light_black)
      elsif data['correct']
        # Correct answer
        points_text = data['points'] > 0 ? " (+#{data['points']} points)" : ""
        puts "   ✅ CORRECT! Your answer was correct: #{data['answer']}#{points_text}".colorize(:green)

        # Show bonus points details if applicable
        if data['points'] > 10 # More than base points
          bonus = data['points'] - 10
          puts "   🎉 SPEED BONUS: +#{bonus} points for fast answer!".colorize(:light_yellow)
        end
      else
        # Incorrect answer
        puts "   ❌ INCORRECT! The correct answer was: #{data['correct_answer']}".colorize(:red)
        puts "   You answered: #{data['answer']} (0 points)".colorize(:yellow)
      end

      puts "\n   Waiting for the round to complete. Please wait for the next question...".colorize(:light_blue)
    end

    # Handle round results showing all players' answers
    def handle_round_result(data)
      # Invalidate any running timer and reset window title
      @current_timer_id = SecureRandom.uuid
      print "\033]0;Git Game Show - Round Results\007"  # Reset window title with context

      # Start with a clean screen
      clear_screen

      puts "\n"

      # Box is drawn with exactly 45 "━" characters for the top and bottom borders
      # The top and bottom including borders are 48 characters wide
      box_width = 40
      box_top    = ("╭" + "─" * box_width + "╮").center(@game_width)
      box_bottom = ("╰" + "─" * box_width + "╯").center(@game_width)
      box_middle = "│#{'Round Results'.center(box_width)}│".center(@game_width)

      # Output the box
      puts box_top.colorize(:light_blue)
      puts box_middle.colorize(:light_blue)
      puts box_bottom.colorize(:light_blue)
      puts "\n"

      # Show question again
      puts "   Question: #{data['question'][:question]}".colorize(:light_blue)

      # Handle different display formats for correct answers
      if data['question'][:question_type] == 'ordering' && data['correct_answer'].is_a?(Array)
        puts "   Correct order (oldest to newest):".colorize(:green)
        data['correct_answer'].each do |item|
          puts "     #{item}".colorize(:green)
        end
      else
        puts "   Correct answer: #{data['correct_answer']}".colorize(:green)
      end

      puts "\n   All player results:".colorize(:light_blue)

      # Debug data temporarily removed

      # Handle results based on structure
      if data['results'].is_a?(Hash)
        data['results'].each do |player, result|
          # Ensure result is a hash with the expected keys
          if result.is_a?(Hash)
            # Check if 'correct' is a boolean or check string equality if it's a string
            correct = result[:correct] || result['correct'] || false
            answer = result[:answer] || result['answer'] || "No answer"
            points = result[:points] || result['points'] || 0

            status = correct ? "✓" : "✗"
            points_str = "(+#{points} points)"
            player_str = player == name ? "#{player} (You)" : player

            # For ordering questions with array answers, show them with numbers
            if data['question'][:question_type] == 'ordering' && answer.is_a?(Array)
              # First display player name and points
              header = "   #{player_str.ljust(20)} #{points_str.ljust(15)} #{status}"

              # Color according to correctness
              if correct
                puts header.colorize(:green)
                puts "     Submitted order:".colorize(:green)
                answer.each_with_index do |item, idx|
                  puts "       #{idx + 1}. #{item}".colorize(:green)
                end
              else
                puts header.colorize(:red)
                puts "     Submitted order:".colorize(:red)
                answer.each_with_index do |item, idx|
                  puts "       #{idx + 1}. #{item}".colorize(:red)
                end
              end
            else
              # Standard display for non-ordering questions
              player_output = "   #{player_str.ljust(20)} #{points_str.ljust(15)} #{answer} #{status}"
              if correct
                puts player_output.colorize(:green)
              else
                puts player_output.colorize(:red)
              end
            end
          else
            # Fallback for unexpected result format
            puts "   #{player}: #{result.inspect}".colorize(:yellow)
          end
        end
      else
        # Fallback message if results isn't a hash
        puts "   No detailed results available".colorize(:yellow)
      end

      # Display current scoreboard
      if data['scores']
        puts "\n   Current Standings:".colorize(:yellow)
        data['scores'].each_with_index do |(player, score), index|
          player_str = player == name ? "#{player} (You)" : player
          rank = index + 1

          # Add medal emoji for top 3
          rank_display = case rank
                        when 1 then "🥇"
                        when 2 then "🥈"
                        when 3 then "🥉"
                        else "#{rank}."
                        end

          output = "   #{rank_display} #{player_str.ljust(20)} #{score} points"

          if player == name
            puts output.colorize(:light_yellow)
          else
            puts output.colorize(:light_blue)
          end
        end
      end

      puts "\n   Next question coming up automatically...".colorize(:yellow)
    end

    def handle_scoreboard(data)
      # Invalidate any running timer and reset window title
      @current_timer_id = SecureRandom.uuid
      print "\033]0;Git Game Show - Scoreboard\007"  # Reset window title with context

      # Always start with a clean screen for the scoreboard
      clear_screen

      box_width = 40
      puts ""
      puts ("╭" + "─" * box_width + "╮").center(@game_width).colorize(:yellow)
      puts "│#{'Scoreboard'.center(box_width)}┃".center(@game_width).colorize(:yellow)
      puts ("╰" + "─" * box_width + "╯").center(@game_width).colorize(:yellow)
      puts "\n"

      # Get player positions
      position = 1
      last_score = nil

      data['scores'].each do |player, score|
        # Determine position (handle ties)
        position = data['scores'].values.index(score) + 1 if last_score != score
        last_score = score

        # Highlight current player
        player_str = player == name ? "#{player} (You)" : player

        # Format with position
        position_str = "#{position}."
        score_str = "#{score} points"

        # Add emoji for top 3
        case position
        when 1
          position_str = "🥇 #{position_str}"
          puts "   #{position_str.ljust(5)} #{player_str.ljust(25)} #{score_str}".colorize(:light_yellow)
        when 2
          position_str = "🥈 #{position_str}"
          puts "   #{position_str.ljust(5)} #{player_str.ljust(25)} #{score_str}".colorize(:light_blue)
        when 3
          position_str = "🥉 #{position_str}"
          puts "   #{position_str.ljust(5)} #{player_str.ljust(25)} #{score_str}".colorize(:light_magenta)
        else
          puts "   #{position_str.ljust(5)} #{player_str.ljust(25)} #{score_str}"
        end
      end

      puts "\n   Next round coming up soon...".colorize(:light_blue)
    end

    def handle_game_end(data)
      # Invalidate any running timer and reset window title
      @current_timer_id = SecureRandom.uuid
      print "\033]0;Git Game Show - Game Over\007"  # Reset window title with context

      # Clear any timer status line at the bottom
      term_height = `tput lines`.to_i rescue 24
      print "\e7"              # Save cursor position
      print "\e[#{term_height};1H"  # Move to bottom line
      print "\e[K"             # Clear line
      print "\e8"              # Restore cursor position

      # Completely clear the screen
      clear_screen
      @game_state = :ended

      winner = data['winner']

      # ASCII trophy art
      trophy = [
       "___________",
      "'._==_==_=_.'",
      ".-\\:      /-.",
     "| (|:.     |) |",
      "'-|:.     |-'",
       "\\::.    /",
        "'::. .'",
          ") (",
        "_.' '._"
     ]

      box_width = 40
      puts "\n\n"
      trophy.each{|line| puts line.center(@game_width).colorize(:yellow)}
      puts "\n"
      puts ("╭" + "─" * box_width + "╮").center(@game_width).colorize(:green)
      puts "│#{'Game Over'.center(box_width)}│".center(@game_width).colorize(:green)
      puts ("╰" + "─" * box_width + "╯").center(@game_width).colorize(:green)
      puts "\n"

      winner_is_you = winner == name
      if winner_is_you
        puts "🎉 Congratulations! You won! 🎉".center(@game_width).colorize(:light_yellow)
      else
        puts "Winner: #{winner}! 🏆".center(@game_width).colorize(:light_yellow)
      end

      puts ""
      puts "Final Scores".center(@game_width).colorize(:light_blue)
      puts ""

      # Get player positions
      position = 1
      last_score = nil

      data['scores'].each do |player, score|
        # Determine position (handle ties)
        position = data['scores'].values.index(score) + 1 if last_score != score
        last_score = score

        # Highlight current player
        player_str = player == name ? "#{player} (You)" : player

        # Format with position
        position_str = "#{position}."
        score_str = "#{score} points"

        # Add emoji for top 3
        scores_width = @game_width - 30
        case position
        when 1
          position_str = "🥇 #{position_str}"
          left_string = (position_str.rjust(5) + ' ' + player_str).ljust(scores_width - score_str.length)
          puts "#{left_string}#{score_str}".center(@game_width).colorize(:light_yellow)
        when 2
          position_str = "🥈 #{position_str}"
          left_string = (position_str.rjust(5) + ' ' + player_str).ljust(scores_width - score_str.length)
          puts "#{left_string}#{score_str}".center(@game_width).colorize(:light_blue)
        when 3
          position_str = "🥉 #{position_str}"
          left_string = (position_str.rjust(5) + ' ' + player_str).ljust(scores_width - score_str.length)
          puts "#{left_string}#{score_str}".center(@game_width).colorize(:light_magenta)
        else
          left_string = "  " + (position_str.rjust(5) + ' ' + player_str).ljust(scores_width - score_str.length)
          puts "#{left_string}#{score_str}".center(@game_width)
        end
      end

      puts "\n"
      puts "   Thanks for playing Git Game Show!".colorize(:green)
      puts "   Waiting for the host to start a new game...".colorize(:light_blue)
      puts "   Press Ctrl+C to exit, or wait for the next game".colorize(:light_black)

      # Keep client ready to receive a new game start or reset message
      @game_over_timer = Thread.new do
        begin
          loop do
            # Just keep waiting for host to start a new game
            # The client will receive GAME_START or GAME_RESET when the host takes action
            sleep 1
          end
        rescue => e
          # Silence any errors in the waiting thread
        end
      end
    end

    # Add a special method to handle game reset notifications
    def handle_game_reset(data)
      # Stop the game over timer if it's running
      @game_over_timer&.kill if @game_over_timer&.alive?

      # Reset game state
      @game_state = :lobby

      # Clear any lingering state
      @players = @players || [] # Keep existing players list if we have one

      # Show the waiting room again
      clear_screen
      display_waiting_room

      # Show a prominent message that we're back in waiting room mode
      puts "\n  🔄 The game has been reset by the host. Waiting for a new game to start...".colorize(:light_blue)
      puts "  You can play again or press Ctrl+C to exit.".colorize(:light_blue)
    end

    def handle_chat(data)
      puts "[#{data['sender']}]: #{data['message']}".colorize(:light_blue)
    end

    def send_message(message)
      begin
        @ws.send(message.to_json)
      rescue => e
        puts "Error sending message: #{e.message}".colorize(:red)
      end
    end
  end
end
