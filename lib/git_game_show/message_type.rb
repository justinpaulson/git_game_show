module GitGameShow
  # Message types for client-server communication
  module MessageType
    JOIN_REQUEST = 'join_request'
    JOIN_RESPONSE = 'join_response'
    PLAYER_JOINED = 'player_joined'
    PLAYER_LEFT = 'player_left'
    GAME_START = 'game_start'
    GAME_END = 'game_end'
    GAME_RESET = 'game_reset'
    QUESTION = 'question'
    ANSWER = 'answer'
    ANSWER_FEEDBACK = 'answer_feedback'
    ROUND_RESULT = 'round_result'
    SCOREBOARD = 'scoreboard'
    CHAT = 'chat'
  end
end