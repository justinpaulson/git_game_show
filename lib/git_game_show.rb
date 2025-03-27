require 'git'
require 'colorize'
require 'tty-prompt'
require 'tty-table'
require 'tty-cursor'
require 'json'
require 'eventmachine'
require 'websocket-eventmachine-server'
require 'websocket-client-simple'
require 'thor'
require 'uri'
require 'clipboard'
require 'readline'
require 'timeout'
require 'net/http'

# Define module and constants first before loading any other files
module GitGameShow
  # VERSION is defined in version.rb

  # Default configuration
  DEFAULT_CONFIG = {
    internal_port: 80,
    rounds: 3,
    question_timeout: 30, # seconds
    question_display_time: 5, # seconds to show results before next question
    transition_delay: 10 # seconds between rounds
  }.freeze

  # File structure is now:
  # 1. Load core message types first
  # 2. Load version file
  # 3. Load core files
  # 4. Load UI components
  # 5. Load network components
  # 6. Load main coordination files (server_handler, game_server)
  # 7. Load mini-games
end

# Load message types
require_relative 'git_game_show/message_type'

# Load version file
require_relative 'git_game_show/version'

# Load core components
require_relative 'git_game_show/core/game_state'
require_relative 'git_game_show/core/player_manager'
require_relative 'git_game_show/core/mini_game_loader'
require_relative 'git_game_show/core/question_manager'

# Load UI components
require_relative 'git_game_show/ui/renderer'
require_relative 'git_game_show/ui/sidebar'
require_relative 'git_game_show/ui/console'
require_relative 'git_game_show/ui/welcome_screen'

# Load network components
require_relative 'git_game_show/network/server'
require_relative 'git_game_show/network/message_handler'

# Load coordination files
require_relative 'git_game_show/server_handler'
require_relative 'git_game_show/game_server'

# Load other required files
require_relative 'git_game_show/cli'
require_relative 'git_game_show/mini_game'
require_relative 'git_game_show/player_client'
require_relative 'git_game_show/updater' if File.exist?(File.join(__dir__, 'git_game_show', 'updater.rb'))

# Load all mini-games
Dir[File.join(__dir__, '..', 'mini_games', '*.rb')].sort.each { |file| require file }