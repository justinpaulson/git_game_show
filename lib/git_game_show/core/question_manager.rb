module GitGameShow
  # Manages question generation, evaluation, and scoring
  class QuestionManager
    def initialize(game_state, player_manager)
      @game_state = game_state
      @player_manager = player_manager
    end

    def generate_questions(repo)
      mini_game = @game_state.current_mini_game
      return [] unless mini_game

      begin
        questions = mini_game.generate_questions(repo)
        @game_state.set_round_questions(questions)
        questions
      rescue => e
        # Handle error gracefully
        []
      end
    end

    def evaluate_answers
      return false if @game_state.question_already_evaluated
      
      @game_state.mark_question_evaluated
      current_question = @game_state.current_question
      return false unless current_question

      mini_game = @game_state.current_mini_game
      return false unless mini_game

      player_answers = @game_state.player_answers

      results = {}

      if current_question[:question_type] == 'ordering'
        # Convert player_answers to the format expected by mini-game's evaluate_answers
        mini_game_answers = {}
        player_answers.each do |player_name, answer_data|
          next unless player_name && answer_data
          
          mini_game_answers[player_name] = {
            answer: answer_data[:answer],
            time_taken: answer_data[:time_taken] || 20
          }
        end

        # Call the mini-game's evaluate_answers method
        begin
          results = mini_game.evaluate_answers(current_question, mini_game_answers) || {}
        rescue => e
          # Create fallback results in case of error
          player_answers.each do |player_name, answer_data|
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
        # For regular quizzes, use pre-calculated points
        player_answers.each do |player_name, answer_data|
          next unless player_name && answer_data

          results[player_name] = {
            answer: answer_data[:answer] || "No answer",
            correct: answer_data[:correct] || false,
            points: answer_data[:points] || 0
          }
        end
      end

      # Update scores in player manager
      results.each do |player, result|
        @player_manager.update_score(player, result[:points] || 0)
      end

      # Format correct answer for ordering questions
      if current_question[:question_type] == 'ordering'
        formatted_correct_answer = current_question[:correct_answer].map.with_index do |item, idx|
          "#{idx + 1}. #{item}" # Add numbers for easier reading
        end
        current_question[:formatted_correct_answer] = formatted_correct_answer
      end

      # Return the results and the current question
      return {
        results: results,
        question: current_question
      }
    end

    def question_timeout
      # Get mini-game specific timeout if available
      if @game_state.current_mini_game.class.respond_to?(:question_timeout)
        timeout = @game_state.current_mini_game.class.question_timeout.to_i
        return timeout > 0 ? timeout : 20
      end
      
      # Default timeout
      GitGameShow::DEFAULT_CONFIG[:question_timeout] || 20
    end

    def question_display_time
      # Get mini-game specific display time if available
      if @game_state.current_mini_game.class.respond_to?(:question_display_time)
        display_time = @game_state.current_mini_game.class.question_display_time.to_i
        return display_time > 0 ? display_time : 5
      end
      
      # Default display time
      GitGameShow::DEFAULT_CONFIG[:question_display_time] || 5
    end
  end
end