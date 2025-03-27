module GitGameShow
  # Handles console input and command processing
  class Console
    def initialize(server_handler, renderer)
      @server_handler = server_handler
      @renderer = renderer
    end

    def setup_command_handler
      # Log initial instructions
      @renderer.log_message("Available commands: help, start, exit", :cyan)
      @renderer.log_message("Type a command and press Enter", :cyan)
      @renderer.log_message("Server is running. Waiting for players to join...", :green)

      # Handle commands in a separate thread
      Thread.new do
        loop do
          @renderer.draw_command_prompt
          command = gets&.chomp&.downcase
          next unless command

          # Process commands
          handle_command(command)
          
          # Small delay to process any display changes
          sleep 0.1
        end
      end
    end

    private

    def handle_command(command)
      case command
      when 'start'
        @server_handler.handle_start_command
      when 'help'
        show_help
      when 'end'
        @server_handler.handle_end_command
      when 'reset'
        @server_handler.handle_reset_command
      when 'exit'
        handle_exit_command
      else
        @renderer.log_message("Unknown command: #{command}. Type 'help' for available commands.", :red)
      end
    end

    def show_help
      @renderer.log_message("Available commands:", :cyan)
      @renderer.log_message("  start   - Start the game with current players", :cyan)
      @renderer.log_message("  end     - End current game and show final scores", :cyan)
      @renderer.log_message("  reset   - Manually reset players to waiting room (after game ends)", :cyan)
      @renderer.log_message("  help    - Show this help message", :cyan)
      @renderer.log_message("  exit    - Shut down the server and exit", :cyan)
    end

    def handle_exit_command
      # Clean up before exiting
      @renderer.log_message("Shutting down server...", :yellow)
      @renderer.cleanup
      EM.stop_event_loop
    end
  end
end