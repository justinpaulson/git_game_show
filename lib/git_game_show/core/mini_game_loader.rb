module GitGameShow
  # Handles loading and selecting mini-games
  class MiniGameLoader
    attr_reader :mini_games

    def initialize
      @mini_games = load_mini_games
      @used_mini_games = []
      @available_mini_games = []
    end

    def select_next_mini_game
      # Special case for when only one mini-game type is enabled
      if @mini_games.size == 1
        return @mini_games.first.new
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
      end

      # Select a random game from the available ones
      selected_game = @available_mini_games.sample
      return @mini_games.first.new if selected_game.nil? # Fallback for safety

      # Remove the selected game from available and add to used
      @available_mini_games.delete(selected_game)
      @used_mini_games << selected_game

      # Return a new instance of the selected game class
      selected_game.new
    end

    private

    def load_mini_games
      # Enable all mini-games
      [
        GitGameShow::AuthorQuiz,
        GitGameShow::FileQuiz,
        GitGameShow::CommitMessageCompletion,
        GitGameShow::DateOrderingQuiz,
        GitGameShow::BranchDetective,
        GitGameShow::BlameGame
      ]
    end
  end
end