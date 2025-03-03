module GitGameShow
  class DateOrderingQuiz < MiniGame
    self.name = "Commit Timeline"
    self.description = "Put these commits in chronological order! (20 seconds per question)"
    self.questions_per_round = 5
    
    # Custom timing for this mini-game
    def self.question_timeout
      20 # 20 seconds per question
    end
    
    def self.question_display_time
      5 # 5 seconds between questions
    end
    
    def generate_questions(repo)
      begin
        # Get commits with valid dates
        all_commits = get_all_commits(repo)
        commits = all_commits.select { |commit| commit.date.is_a?(Time) || commit.date.respond_to?(:to_time) }
        
        # If we don't have enough commits for the game, generate sample questions
        if commits.size < 10
          return generate_sample_questions
        end
      rescue => e
        # If any errors occur, fall back to sample questions
        return generate_sample_questions
      end
      
      questions = []
      
      # Generate questions
      self.class.questions_per_round.times do
        begin
          # Get 4 random commits for each question, ensure they have different dates
          # to avoid ties in the ordering
          pool = commits.dup
          selected_commits = []
          
          # Select 4 commits with different dates
          while selected_commits.size < 4 && !pool.empty?
            commit = pool.sample
            pool.delete(commit)
            
            # Check if date is unique among selected commits
            date_duplicate = selected_commits.any? do |selected|
              # Convert dates to Time objects for comparison
              commit_time = commit.date.is_a?(Time) ? commit.date : commit.date.to_time
              selected_time = selected.date.is_a?(Time) ? selected.date : selected.date.to_time
              
              # Check if times are within 1 minute of each other (avoid duplicates)
              (commit_time - selected_time).abs < 60
            end
            
            selected_commits << commit unless date_duplicate
          end
          
          # If we couldn't get 4 commits with different dates, try again with the full pool
          if selected_commits.size < 4
            selected_commits = commits.sample(4)
          end
          
          # Create the options using commit message and short SHA
          options = selected_commits.map do |commit|
            # Get first line of commit message, handle multi-line messages
            message = commit.message.lines.first&.strip || "No message"
            # Truncate long messages to keep UI clean
            message = message.length > 40 ? "#{message[0...37]}..." : message
            "#{message} (#{commit.sha[0..6]})"
          end
          
          # Shuffle options for initial display
          shuffled_options = options.shuffle
          
          # Determine correct order by date
          correct_order = selected_commits.sort_by(&:date).map do |commit|
            message = commit.message.lines.first&.strip || "No message"
            message = message.length > 40 ? "#{message[0...37]}..." : message
            "#{message} (#{commit.sha[0..6]})"
          end
          
          # Get commit dates for displaying in results
          commit_dates = selected_commits.map do |commit|
            date_string = commit.date.strftime('%Y-%m-%d %H:%M:%S')
            "#{commit.sha[0..6]}: #{date_string}"
          end
          
          # Store the question data
          questions << {
            question: "Put these commits in chronological order (oldest to newest):",
            options: shuffled_options,
            correct_answer: correct_order,
            question_type: 'ordering',
            commit_dates: commit_dates.join("\n") # Store dates for feedback
          }
        rescue => e
          # If this question fails, continue to the next one
          next
        end
      end
      
      # If we couldn't generate enough questions, fill with sample questions
      if questions.size < self.class.questions_per_round
        sample_questions = generate_sample_questions
        questions += sample_questions[0...(self.class.questions_per_round - questions.size)]
      end
      
      questions
    end
    
    # Generate sample questions when we don't have enough commits
    def generate_sample_questions
      questions = []
      
      # Sample data sets with commit messages and dates
      sample_data = [
        [
          { message: "Initial commit", sha: "a1b2c3d", date: "2023-01-01 09:00:00" },
          { message: "Add user authentication", sha: "e4f5g6h", date: "2023-01-05 14:30:00" },
          { message: "Fix login page styling", sha: "i7j8k9l", date: "2023-01-10 11:15:00" },
          { message: "Implement password reset", sha: "m2n3o4p", date: "2023-01-15 16:45:00" }
        ],
        [
          { message: "Create README.md", sha: "q5r6s7t", date: "2023-02-01 10:00:00" },
          { message: "Setup test framework", sha: "u8v9w0x", date: "2023-02-07 13:20:00" },
          { message: "Add CI pipeline config", sha: "y1z2a3b", date: "2023-02-14 09:45:00" },
          { message: "Implement first unit tests", sha: "c4d5e6f", date: "2023-02-20 15:30:00" }
        ],
        [
          { message: "Create database schema", sha: "g7h8i9j", date: "2023-03-05 11:00:00" },
          { message: "Add User model", sha: "k1l2m3n", date: "2023-03-10 14:15:00" },
          { message: "Implement data validation", sha: "o4p5q6r", date: "2023-03-18 10:30:00" },
          { message: "Add database migrations", sha: "s7t8u9v", date: "2023-03-25 16:00:00" }
        ],
        [
          { message: "Initial API endpoints", sha: "w0x1y2z", date: "2023-04-02 09:30:00" },
          { message: "Add authentication middleware", sha: "a3b4c5d", date: "2023-04-08 13:45:00" },
          { message: "Implement rate limiting", sha: "e6f7g8h", date: "2023-04-15 11:20:00" },
          { message: "Add API documentation", sha: "i9j0k1l", date: "2023-04-22 15:10:00" }
        ],
        [
          { message: "Create frontend structure", sha: "m2n3o4p", date: "2023-05-01 10:15:00" },
          { message: "Implement login component", sha: "q5r6s7t", date: "2023-05-09 14:00:00" },
          { message: "Add dashboard UI", sha: "u8v9w0x", date: "2023-05-17 11:30:00" },
          { message: "Fix responsive design issues", sha: "y1z2a3b", date: "2023-05-25 16:45:00" }
        ]
      ]
      
      # Generate one question from each sample set
      self.class.questions_per_round.times do |i|
        # Use modulo to cycle through samples if we have fewer samples than questions
        sample_set = sample_data[i % sample_data.size]
        
        # Format the options
        options = sample_set.map { |item| "#{item[:message]} (#{item[:sha]})" }
        
        # Determine correct order (they're already in order in our samples)
        correct_order = options.dup
        
        # Shuffle options for initial display
        shuffled_options = options.shuffle
        
        # Format dates for feedback
        date_strings = sample_set.map { |item| "#{item[:sha]}: #{item[:date]}" }
        
        questions << {
          question: "Put these commits in chronological order (oldest to newest):",
          options: shuffled_options,
          correct_answer: correct_order, 
          question_type: 'ordering',
          commit_dates: date_strings.join("\n")
        }
      end
      
      questions
    end
    
    def evaluate_answers(question, player_answers)
      results = {}
      
      player_answers.each do |player_name, answer_data|
        player_answer = answer_data[:answer]
        time_taken = answer_data[:time_taken] || 20
        
        # For the ordering quiz, we allow partial credit
        correct_positions = 0
        
        # Count how many items are in the correct position
        question[:correct_answer].each_with_index do |item, index|
          if player_answer && index < player_answer.size && player_answer[index] == item
            correct_positions += 1
          end
        end
        
        # Calculate points: full credit for all correct, partial for some correct
        total_items = question[:correct_answer].size
        points = (correct_positions.to_f / total_items * 10).round
        
        # Fully correct gets bonus points
        if correct_positions == total_items
          # Base bonus for fully correct answer
          points += 3
          
          # Additional time-based bonus (faster answers get more points)
          if time_taken < 8  # Really fast (under 8 seconds)
            points += 4
          elsif time_taken < 14  # Pretty fast (under 14 seconds)
            points += 2
          end
        end
        
        # Create feedback with date info for displaying in results
        feedback = "#{correct_positions}/#{total_items} positions correct"
        if question[:commit_dates]
          feedback += "\n\nActual dates:\n" + question[:commit_dates]
        end
        
        results[player_name] = {
          answer: player_answer,
          correct: correct_positions == total_items,
          points: points,
          partial_score: feedback
        }
      end
      
      results
    end
  end
end