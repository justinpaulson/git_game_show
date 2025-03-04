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
    port: 3030,
    rounds: 3,
    question_timeout: 30, # seconds
    question_display_time: 5, # seconds to show results before next question
    transition_delay: 5 # seconds between rounds
  }.freeze
  
  # Message types for WebSocket communication
  module MessageType
    JOIN_REQUEST = 'join_request'
    JOIN_RESPONSE = 'join_response'
    GAME_START = 'game_start'
    QUESTION = 'question'
    ANSWER = 'answer'
    ANSWER_FEEDBACK = 'answer_feedback' # New message type for immediate feedback
    ROUND_RESULT = 'round_result'
    SCOREBOARD = 'scoreboard'
    GAME_END = 'game_end'
    GAME_RESET = 'game_reset' # New message type for resetting the game
    CHAT = 'chat'
  end
end

# Load all files in the git_game_show directory
Dir[File.join(__dir__, 'git_game_show', '*.rb')].sort.each { |file| require file }

# Load all mini-games
Dir[File.join(__dir__, '..', 'mini_games', '*.rb')].sort.each { |file| require file }