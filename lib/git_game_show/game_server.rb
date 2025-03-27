module GitGameShow
  # Main Game Server class - now a lightweight coordinator of other components
  class GameServer
    attr_reader :port, :password, :rounds, :repo, :players, :current_round, :game_state

    def initialize(port:, password:, rounds:, repo:)
      @port = port
      @password = password
      @rounds = rounds
      @repo = repo

      # These are kept for backward compatibility but not used directly
      @players = {}
      @scores = {}
      @current_round = 0
      @game_state = :lobby
    end

    def start
      # Legacy method for starting the server without UI
      EM.run do
        server_handler = ServerHandler.new(
          port: @port,
          password: @password,
          rounds: @rounds,
          repo: @repo
        )

        # Start server with minimal UI
        puts "Server running at ws://0.0.0.0:#{@port}".colorize(:green)
        server_handler.start_with_ui
      end
    end

    def start_with_ui(join_link = nil)
      # Store the join_link
      @join_link = join_link

      # Initialize and start the server handler with UI
      @server_handler = ServerHandler.new(
        port: @port,
        password: @password,
        rounds: @rounds,
        repo: @repo
      )

      # Start the server with UI
      @server_handler.start_with_ui(@join_link)
    end

    # Legacy method definitions for backwards compatibility

    def draw_ui_frame
      # Forward to renderer
      @server_handler&.instance_variable_get(:@renderer)&.draw_ui_frame
    end

    def draw_welcome_banner
      # Forward to renderer
      @server_handler&.instance_variable_get(:@renderer)&.draw_welcome_banner
    end

    def draw_join_link
      # Forward to renderer
      @server_handler&.instance_variable_get(:@renderer)&.draw_join_link(@join_link) if @join_link
    end

    def draw_sidebar
      # Forward to sidebar
      @server_handler&.instance_variable_get(:@sidebar)&.draw_header
    end

    def draw_command_prompt
      # Forward to renderer
      @server_handler&.instance_variable_get(:@renderer)&.draw_command_prompt
    end

    def log_message(message, color = :white)
      # Forward to renderer
      @server_handler&.instance_variable_get(:@renderer)&.log_message(message, color)
    end

    def update_player_list
      # Forward to sidebar
      player_manager = @server_handler&.instance_variable_get(:@player_manager)
      sidebar = @server_handler&.instance_variable_get(:@sidebar)

      if player_manager && sidebar
        sidebar.update_player_list(player_manager.players, player_manager.scores)
      end
    end
  end
end
