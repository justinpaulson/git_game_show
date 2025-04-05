module GitGameShow
  # Manages player connections, scores, and related operations
  class PlayerManager
    attr_reader :players, :scores

    def initialize
      @players = {}  # WebSocket connections by player name
      @scores = {}   # Player scores
    end

    def add_player(name, ws)
      return false if @players.key?(name)
      @players[name] = ws
      @scores[name] = 0
      true
    end

    def remove_player(name)
      return false unless @players.key?(name)
      @players.delete(name)
      true
    end

    def find_player_by_ws(ws)
      @players.key(ws)
    end

    def player_exists?(name)
      @players.key?(name)
    end

    def get_ws(name)
      @players[name]
    end

    def player_count
      @players.size
    end

    def player_names
      @players.keys
    end

    def update_score(name, points)
      @scores[name] = (@scores[name] || 0) + points
    end

    def reset_scores
      @players.keys.each { |name| @scores[name] = 0 }
    end

    def sorted_scores
      @scores.sort_by { |_, score| -score }.to_h
    end

    def top_player
      sorted = sorted_scores
      sorted.empty? ? nil : sorted.first
    end
  end
end