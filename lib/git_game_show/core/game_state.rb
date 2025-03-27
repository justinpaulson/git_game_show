module GitGameShow
  # Manages the state of the game
  class GameState
    attr_reader :state, :current_round, :total_rounds, :current_mini_game
    attr_reader :round_questions, :current_question_index, :question_start_time
    attr_reader :player_answers, :current_question_id, :question_already_evaluated

    def initialize(total_rounds)
      @total_rounds = total_rounds
      @current_round = 0
      @state = :lobby  # :lobby, :playing, :ended
      @current_mini_game = nil
      @round_questions = []
      @current_question_index = 0
      @question_start_time = nil
      @player_answers = {}
      @current_question_id = nil
      @question_already_evaluated = false
      @used_mini_games = []  # Track which mini-games have been used
      @available_mini_games = []  # Mini-games still available in the current cycle
    end

    def lobby?
      @state == :lobby
    end

    def playing?
      @state == :playing
    end

    def ended?
      @state == :ended
    end

    def start_game
      return false unless @state == :lobby
      @state = :playing
      @current_round = 0
      # Reset the mini-game tracking for a new game
      @used_mini_games = []
      @available_mini_games = []
      true
    end

    def end_game
      @state = :ended
      true
    end

    def reset_game
      @state = :lobby
      @current_round = 0
      @current_mini_game = nil
      @round_questions = []
      @current_question_index = 0
      @question_already_evaluated = false
      @player_answers = {}
      true
    end

    def start_next_round(mini_game)
      @current_round += 1
      # Reset question evaluation flag for the new round
      @question_already_evaluated = false
      
      # Set the current mini-game
      @current_mini_game = mini_game
      true
    end

    def set_round_questions(questions)
      @round_questions = questions
      @current_question_index = 0
      true
    end

    def prepare_next_question
      return false if @current_question_index >= @round_questions.size
      
      @question_already_evaluated = false
      @current_question_id = "#{@current_round}-#{@current_question_index}"
      @question_start_time = Time.now
      @player_answers = {}
      true
    end

    def current_question
      return nil if @current_question_index >= @round_questions.size
      @round_questions[@current_question_index]
    end

    def move_to_next_question
      @current_question_index += 1
      @player_answers = {}
      @question_already_evaluated = false
    end

    def last_question_in_round?
      @current_question_index >= @round_questions.size - 1
    end

    def last_round?
      @current_round >= @total_rounds
    end

    def record_player_answer(player_name, answer, time_taken, correct = nil, points = 0)
      @player_answers[player_name] = {
        answer: answer,
        time_taken: time_taken,
        answered: true,
        correct: correct,
        points: points
      }
    end

    def mark_question_evaluated
      @question_already_evaluated = true
    end
  end
end