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
      
      # Safety check for nil or empty responses
      return results if player_answers.nil? || player_answers.empty?
      return results unless question && question[:correct_answer]
      
      # Get total number of items in the correct answer
      total_items = question[:correct_answer].size
      
      player_answers.each do |player_name, answer_data|
        # Skip nil entries
        next unless player_name && answer_data
        
        # Extract player's answer with defensive checks
        player_answer = answer_data[:answer]
        time_taken = answer_data[:time_taken] || 20
        
        # Initialize points
        points = 0
        
        # New scoring system: checks positions relative to each other item
        if player_answer && !player_answer.empty?
          # Create a mapping from item to its position in player's answer
          item_positions = {}
          player_answer.each_with_index do |item, index|
            item_positions[item] = index if item # Skip nil items
          end
          
          # Create mapping from item to correct position
          correct_positions = {}
          question[:correct_answer].each_with_index do |item, index|
            correct_positions[item] = index if item # Skip nil items
          end
          
          # For each item, calculate points based on relative positions
          question[:correct_answer].each_with_index do |item, correct_index|
            # Skip if the item isn't in the player's answer
            next unless item && item_positions.key?(item)
            
            player_index = item_positions[item]
            
            # Check position relative to other items
            question[:correct_answer].each_with_index do |other_item, other_correct_index|
              next if !other_item || item == other_item || !item_positions.key?(other_item)
              
              other_player_index = item_positions[other_item]
              
              # If this item should be before the other item
              if correct_index < other_correct_index
                points += 1 if player_index < other_player_index
              # If this item should be after the other item
              elsif correct_index > other_correct_index
                points += 1 if player_index > other_player_index
              end
            end
          end
        end
        
        # Bonus points for perfect answer
        perfect_score = total_items * (total_items - 1)
        perfect_score = 1 if perfect_score <= 0 # Prevent division by zero
        fully_correct = points == perfect_score
        
        if fully_correct
          # Additional time-based bonus (faster answers get more points)
          if time_taken < 8  # Really fast (under 8 seconds)
            points += 4
          elsif time_taken < 14  # Pretty fast (under 14 seconds)
            points += 2
          end
        end
        
        # Create detailed feedback
        max_possible = total_items * (total_items - 1)
        max_possible = 1 if max_possible <= 0 # Prevent division by zero
        feedback = "#{points}/#{max_possible} points (based on relative ordering)"
        if question[:commit_dates]
          feedback += "\n\nActual dates:"
          # Split by newlines and add them as separate lines for better readability
          question[:commit_dates].to_s.split("\n").each do |date_line|
            feedback += "\n  • #{date_line}"
          end
        end
        
        # Ensure we return all required fields
        results[player_name] = {
          answer: player_answer || [],
          correct: fully_correct || false,
          points: points || 0,
          partial_score: feedback || ""
        }
      end
      
      # Return a default result if somehow we ended up with empty results
      if results.empty? && !player_answers.empty?
        player_name = player_answers.keys.first
        results[player_name] = {
          answer: [],
          correct: false,
          points: 0,
          partial_score: "Error calculating score"
        }
      end
      
      results
    end
  end
end