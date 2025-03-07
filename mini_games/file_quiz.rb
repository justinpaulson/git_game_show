module GitGameShow
  # Disable debug mode for normal operation
  $FILE_QUIZ_DEBUG = false

  class FileQuiz < MiniGame
    self.name = "File Quiz"
    self.description = "Match the commit message to the right changed file!"
    self.questions_per_round = 5

    # Custom timing for this mini-game (same as AuthorQuiz)
    def self.question_timeout
      15 # 15 seconds per question
    end

    def self.question_display_time
      5 # 5 seconds between questions
    end

    def generate_questions(repo)
      begin
        # Use the same approach as AuthorQuiz - get ALL commits using the helper method
        commits = get_all_commits(repo)

        # Check if we got any commits at all
        if commits.nil? || commits.empty?
          # Silently fall back to sample questions
          return generate_sample_questions
        end

        # Shuffle commits for better variety
        commits.shuffle!

        # Process commits to find ones with good file changes
        valid_commits = []

        commits.each do |commit|
          # Get changed files for this commit
          changed_files = []

          begin
            # Use standard Git methods instead of run_command (silently)

            # Use git commands quietly without showing output
            if commit.parents.empty?
              # For first commit, get files directly
              cmd = "cd #{repo.dir.path} && git show --name-only --pretty=format: #{commit.sha} 2>/dev/null"
              diff_output = `#{cmd}`
            else
              # For normal commits with parents
              cmd = "cd #{repo.dir.path} && git diff --name-only #{commit.sha}^ #{commit.sha} 2>/dev/null"
              diff_output = `#{cmd}`

              # If diff returns empty, try using show as fallback
              if diff_output.strip.empty?
                cmd = "cd #{repo.dir.path} && git show --name-only --pretty=format: #{commit.sha} 2>/dev/null"
                diff_output = `#{cmd}`
              end
            end

            # Parse the output to get changed files (quietly)
            changed_files = diff_output.split("\n").reject(&:empty?)

            # Skip if no files changed (can't create a question for this)
            next if changed_files.empty?

            # Super relaxed - accept ANY commit with files that changed
            # No more filtering by number of files

            # Create structure with relevant commit data
            valid_commits << {
              sha: commit.sha,
              message: commit.message,
              author: commit.author.name,
              date: commit.date,
              files: changed_files
            }

            # Once we have enough commits, we can stop
            # Get more commits to have a better selection
            break if valid_commits.size >= self.class.questions_per_round * 5
          rescue => e
            # Silently skip problematic commits
            next
          end
        end

        # Never fall back to samples as long as we have at least 1 valid commit
        if valid_commits.empty?
          # Silently fall back to sample questions if needed
          return generate_sample_questions
        end

        # Prioritize commits that modified interesting files (not just .gitignore etc.)
        prioritized_commits = valid_commits.sort_by do |commit|
          # Higher score = more interesting commit
          score = 0

          # Prioritize based on file types
          commit[:files].each do |file|
            ext = File.extname(file).downcase

            case ext
            when '.rb', '.js', '.py', '.java', '.tsx', '.jsx'
              score += 3  # Source code is most interesting
            when '.html', '.css', '.scss'
              score += 2  # Templates and styles are interesting
            when '.md', '.txt', '.json', '.yaml', '.yml'
              score += 1  # Config and docs are moderately interesting
            when '', '.gitignore', '.gitattributes'
              score -= 1  # Less interesting files
            end
          end

          # Prioritize based on commit message length - longer messages are often more descriptive
          message_length = commit[:message].to_s.strip.length
          score += [message_length / 20, 5].min

          # Return negative score so highest scores come first in sort
          -score
        end

        # Take as many commits as we need for questions
        needed_commits = [self.class.questions_per_round, prioritized_commits.size].min
        selected_commits = prioritized_commits.take(needed_commits)

        # Create questions from selected commits
        questions = []

        selected_commits.each do |commit|
          # Choose the most interesting file as the correct answer
          files = commit[:files]

          # Skip if somehow we got a commit with no files
          next if files.empty?

          # Score files by interestingness
          scored_files = files.map do |file|
            ext = File.extname(file).downcase

            # Start with base score by extension
            score = case ext
            when '.rb', '.js', '.py', '.java', '.tsx', '.jsx'
              10  # Source code is most interesting
            when '.html', '.css', '.scss'
              8   # Templates and styles are interesting
            when '.md', '.txt'
              6   # Documentation
            when '.json', '.yaml', '.yml'
              4   # Config files
            when '', '.gitignore', '.gitattributes'
              0   # Less interesting files
            else
              5   # Other files are neutral
            end

            # Shorter paths are usually more recognizable
            score -= [file.length / 10, 5].min

            # Prefer files in main directories (src, lib, app) over deeply nested ones
            if file.start_with?('src/', 'lib/', 'app/')
              score += 3
            end

            [file, score]
          end

          # Sort by score (highest first) and select most interesting file
          scored_files.sort_by! { |_, score| -score }
          correct_file = scored_files.first[0]

          # Get incorrect options from other commits
          other_files = []
          other_commits = selected_commits - [commit]

          # Collect files from other commits
          other_commits.each do |other_commit|
            other_commit[:files].each do |file|
              other_files << file unless files.include?(file)
            end
          end

          # If we don't have enough other files, use some from sample data
          if other_files.size < 3
            sample_files = [
              "src/main.js", "lib/utils.js", "css/styles.css", "README.md",
              "package.json", "Dockerfile", ".github/workflows/ci.yml",
              "src/components/Header.js", "app/models/user.rb", "config/database.yml"
            ]
            other_files += sample_files.reject { |f| files.include?(f) }
          end

          # Take up to 3 unique other files, prioritizing diverse ones
          other_files = other_files.uniq.sample(3)

          # Create options array with the correct answer and incorrect ones
          all_options = ([correct_file] + other_files).shuffle

          # Format the commit date nicely
          nice_date = commit[:date].strftime('%b %d, %Y') rescue "Unknown date"

          # Clean up commit message - take first line if multiple lines
          message = commit[:message].to_s.split("\n").first.strip

          # Format consistently with other mini-games
          questions << {
            question: "Which file was most likely changed in this commit?\n\n   \"#{message}\"",
            commit_info: "#{commit[:sha][0..6]} (#{nice_date})",
            options: all_options,
            correct_answer: correct_file
          }
        end

        # If we still couldn't create enough questions, use a mix of real and samples
        if questions.size < self.class.questions_per_round
          # Add sample questions to fill the remaining slots (silently)
          sample_questions = generate_sample_questions
          remaining_slots = self.class.questions_per_round - questions.size
          questions += sample_questions.take(remaining_slots)
        end

        return questions
      rescue => e
        # If anything fails, silently fall back to sample questions
        return generate_sample_questions
      end
    end

    def evaluate_answers(question, player_answers)
      results = {}

      player_answers.each do |player_name, answer_data|
        answered = answer_data[:answered] || false
        player_answer = answer_data[:answer]
        correct = player_answer == question[:correct_answer]

        points = correct ? 10 : 0

        # Bonus points for fast answers (if correct)
        if correct
          time_taken = answer_data[:time_taken] || 15

          if time_taken < 5
            points += 5
          elsif time_taken < 10
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

    # Generate sample questions only used when no repository data is available
    def generate_sample_questions
      # No debug message in production
      questions = []

      # Common file options
      common_files = [
        "src/main.js",
        "README.md",
        "lib/utils.js",
        "css/styles.css"
      ]

      # Common sample commit messages
      sample_messages = [
        "Update documentation with new API endpoints",
        "Fix styling issues in mobile view",
        "Add error handling for network failures",
        "Refactor authentication module for better performance",
        "Update dependencies to latest versions"
      ]

      # Create different sample questions for variety
      self.class.questions_per_round.times do |i|
        # Use modulo to cycle through sample messages
        message = sample_messages[i % sample_messages.size]

        # Different correct answers for each question
        correct_file = common_files[i % common_files.size]

        # Options are all files with the correct one included
        all_options = common_files.shuffle

        # Create the question - clearly label as sample data
        questions << {
          question: "Which file was most likely changed in this commit?\n\n   \"#{message} (SAMPLE)\"",
          commit_info: "sample#{i} (Demo Question)",
          options: all_options,
          correct_answer: correct_file
        }
      end

      questions
    end
  end
end
