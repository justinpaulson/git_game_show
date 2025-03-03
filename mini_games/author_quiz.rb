module GitGameShow
  class AuthorQuiz < MiniGame
    self.name = "Author Quiz"
    self.description = "Guess which team member made each commit!"
    self.questions_per_round = 5
    
    # Custom timing for this mini-game (overrides default config)
    def self.question_timeout
      15 # 15 seconds per question
    end
    
    def self.question_display_time
      5 # 5 seconds between questions
    end
    
    def generate_questions(repo)
      # For testing, manually add some questions if we can't get meaningful ones from repo
      questions = []
      
      begin
        # Get commits from the past year
        one_year_ago = Time.now - (365 * 24 * 60 * 60) # One year in seconds
        
        # Get all commits
        all_commits = get_all_commits(repo)
        
        # Filter commits from the past year, if any
        commits_from_past_year = all_commits.select do |commit|
          # Be safe with date parsing
          begin
            commit_time = commit.date.is_a?(Time) ? commit.date : Time.parse(commit.date.to_s)
            commit_time > one_year_ago
          rescue
            false # If we can't parse the date, exclude it
          end
        end
        
        # If we don't have enough commits from the past year, use all commits
        commits = commits_from_past_year.size >= 10 ? commits_from_past_year : all_commits
        
        authors = get_commit_authors(commits)
        
        # We need at least 2 authors for this game to be meaningful
        if authors.size < 2
          return generate_sample_questions
        end
        
        # Shuffle all commits to ensure randomness, then select commits for questions
        selected_commits = commits.shuffle.sample(self.class.questions_per_round)
        
        selected_commits.each do |commit|
        # Get the real author
        correct_author = commit.author.name
        
        # Get incorrect options (other authors)
        incorrect_authors = shuffled_excluding(authors, correct_author).take(3)
        
        # Create options array with the correct answer and incorrect ones
        all_options = ([correct_author] + incorrect_authors).shuffle
        
        # Extract the commit message, but handle multi-line messages gracefully
        message_lines = commit.message.lines.reject(&:empty?)
        message_preview = message_lines.first&.strip || "No message"
        
        # For longer messages, add an indication that there's more
        if message_lines.size > 1
          message_preview += "..." 
        end
        
        # Create a more compact question format to avoid overflows
        # Add proper indentation to the commit message with spaces
        questions << {
          question: "Who authored this commit?\n\n   \"#{message_preview}\"",
          commit_info: "#{commit.sha[0..7]} (#{commit.date.strftime('%b %d, %Y')})",
          options: all_options,
          correct_answer: correct_author
        }
      end
      rescue => e
        # Silently fail and use sample questions instead
        return generate_sample_questions
      end
      
      # If we couldn't generate enough questions, add sample ones
      if questions.empty?
        return generate_sample_questions
      end
      
      questions
    end
    
    def generate_sample_questions
      # Create sample questions in case the repo doesn't have enough data
      sample_authors = ["Alice", "Bob", "Charlie", "David", "Emma"]
      
      questions = []
      
      5.times do |i|
        correct_author = sample_authors.sample
        incorrect_authors = sample_authors.reject { |a| a == correct_author }.sample(3)
        
        all_options = ([correct_author] + incorrect_authors).shuffle
        
        questions << {
          question: "Who authored this commit?\n\n   \"Sample commit message ##{i+1}\"",
          commit_info: "abc123#{i} (Jan #{i+1}, 2025)",
          options: all_options,
          correct_answer: correct_author
        }
      end
      
      questions
    end
    
    def evaluate_answers(question, player_answers)
      results = {}
      
      player_answers.each do |player_name, answer_data|
        answered = answer_data[:answered] || false
        player_answer = answer_data[:answer]
        correct = player_answer == question[:correct_answer]
        
        points = correct ? 10 : 0
        
        # Bonus points for fast answers (if correct)
        if correct && answer_data[:time_taken] < 5
          points += 5
        elsif correct && answer_data[:time_taken] < 10
          points += 3
        end
        
        results[player_name] = {
          answer: player_answer,
          correct: correct,
          points: points
        }
      end
      
      results
    end
  end
end