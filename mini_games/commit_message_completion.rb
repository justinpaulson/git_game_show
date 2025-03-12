module GitGameShow
  class CommitMessageCompletion < MiniGame
    self.name = "Complete the Commit"
    self.description = "Complete the missing part of these commit messages! (20 seconds per question)"
    self.example = <<~EXAMPLE
    Complete this commit message:

       "Fix memory __________ in the background worker"

    2d9a45c (Feb 25, 2025)

    Choose your answer:
      usage
      allocation
    \e[0;32;49m> leak\e[0m
      error
    EXAMPLE
    self.questions_per_round = 5

    # Custom timing for this mini-game (20 seconds instead of 15)
    def self.question_timeout
      20 # 20 seconds per question
    end

    def self.question_display_time
      5 # 5 seconds between questions
    end

    def generate_questions(repo)
      begin
        commits = get_all_commits(repo)

        # Filter commits with message length > 10 characters
        valid_commits = commits.select { |commit| commit.message.strip.length > 10 }

        # Fall back to sample questions if not enough valid commits
        if valid_commits.size < self.class.questions_per_round
          return generate_sample_questions
        end
      rescue => e
        # If there's any error, fall back to sample questions
        return generate_sample_questions
      end

      questions = []
      valid_questions = 0
      attempts = 0
      max_attempts = 100  # Prevent infinite loops

      # Keep trying until we have exactly 5 questions or reach max attempts
      while valid_questions < self.class.questions_per_round && attempts < max_attempts
        attempts += 1

        # Get a random commit
        commit = valid_commits.sample
        message = commit.message.strip

        # Split message into beginning and end parts
        words = message.split(/\s+/)

        # Skip if too few words
        if words.size < 4
          next
        end

        # Determine how much to hide (1/3 to 1/2 of words)
        hide_count = [words.size / 3, 2].max
        hide_start = rand(0..(words.size - hide_count))
        hidden_words = words[hide_start...(hide_start + hide_count)]

        # Replace hidden words with blanks
        words[hide_start...(hide_start + hide_count)] = ['________'] * hide_count

        # Create question and actual answer
        question_text = words.join(' ')
        correct_answer = hidden_words.join(' ')

        # Generate incorrect options
        other_messages = get_commit_messages(valid_commits) - [message]
        other_messages_parts = []

        # Get parts of other messages that have similar length
        other_messages.each do |other_msg|
          other_words = other_msg.split(/\s+/)
          if other_words.size >= hide_count
            part_start = rand(0..(other_words.size - hide_count))
            other_messages_parts << other_words[part_start...(part_start + hide_count)].join(' ')
          end
        end

        # Only proceed if we have enough options
        if other_messages_parts.size < 3
          next
        end

        other_options = other_messages_parts.sample(3)

        # Create options array with the correct answer and incorrect ones
        all_options = ([correct_answer] + other_options).shuffle

        # Format consistently with other mini-games
        questions << {
          question: "Complete this commit message:\n\n   \"#{question_text}\"",
          commit_info: "#{commit.sha[0..7]} (#{commit.date.strftime('%b %d, %Y')})",
          options: all_options,
          correct_answer: correct_answer
        }

        valid_questions += 1
      end

      # If we couldn't generate enough questions, fall back to sample questions
      if questions.size < self.class.questions_per_round
        return generate_sample_questions
      end

      questions
    end

    # Generate sample questions when there aren't enough commits
    def generate_sample_questions
      questions = []

      # Sample commit messages that are realistic
      sample_messages = [
        {
          full_message: "Add user authentication with OAuth2 support",
          blank_text: "Add user __________ with OAuth2 support",
          missing_part: "authentication",
          wrong_options: ["registration", "profile", "settings"],
          sha: "f8c7b3e",
          date: "Mar 10, 2025"
        },
        {
          full_message: "Fix memory leak in the background worker process",
          blank_text: "Fix memory __________ in the background worker",
          missing_part: "leak",
          wrong_options: ["usage", "allocation", "error"],
          sha: "2d9a45c",
          date: "Feb 25, 2025"
        },
        {
          full_message: "Update dependencies to latest stable versions",
          blank_text: "Update __________ to latest stable versions",
          missing_part: "dependencies",
          wrong_options: ["documentation", "configurations", "references"],
          sha: "7b3e9d1",
          date: "Mar 5, 2025"
        },
        {
          full_message: "Improve error handling in API response layer",
          blank_text: "Improve error __________ in API response layer",
          missing_part: "handling",
          wrong_options: ["messages", "logging", "codes"],
          sha: "c4e91a2",
          date: "Feb 28, 2025"
        },
        {
          full_message: "Add comprehensive test coverage for payment module",
          blank_text: "Add comprehensive __________ coverage for payment module",
          missing_part: "test",
          wrong_options: ["code", "feature", "security"],
          sha: "9f5d7e3",
          date: "Mar 15, 2025"
        }
      ]

      # Create a question for each sample
      self.class.questions_per_round.times do |i|
        sample = sample_messages[i % sample_messages.size]

        # Create options array with the correct answer and incorrect ones
        all_options = ([sample[:missing_part]] + sample[:wrong_options]).shuffle

        # Format consistently with other mini-games
        questions << {
          question: "Complete this commit message:\n\n   \"#{sample[:blank_text]}\"",
          commit_info: "#{sample[:sha]} (#{sample[:date]})",
          options: all_options,
          correct_answer: sample[:missing_part]
        }
      end

      questions
    end

    def evaluate_answers(question, player_answers)
      results = {}

      player_answers.each do |player_name, answer_data|
        player_answer = answer_data[:answer]
        correct = player_answer == question[:correct_answer]

        points = 0

        if correct
          points = 10 # Base points for correct answer

          # Bonus points for fast answers, adjusted for 20-second time limit
          time_taken = answer_data[:time_taken] || 20
          if time_taken < 7  # Increased from 5 to 7 seconds
            points += 5
          elsif time_taken < 13  # Increased from 10 to 13 seconds
            points += 3
          end
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
