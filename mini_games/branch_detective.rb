module GitGameShow
  class BranchDetective < MiniGame
    self.name = "Branch Detective"
    self.description = "Identify which branch a commit belongs to!"
    self.questions_per_round = 5

    # Custom timing for this mini-game
    def self.question_timeout
      15 # 15 seconds per question
    end

    def self.question_display_time
      5 # 5 seconds between questions
    end

    def generate_questions(repo)
      @repo = repo
      begin
        # Get all branches (both local and remote)
        branches = {}

        # Use Git command to get all local and remote branches

        # get all remote branches from the git repository
        all_remotes_cmd = "cd #{@repo.dir.path} && git branch -r"
        all_branch_output = `#{all_remotes_cmd}`

        # Parse branch names and clean them up
        branch_names = all_branch_output.split("\n").map do |branch|
          branch = branch.gsub(/^\* /, '').strip  # Remove the * prefix from current branch

          # Skip special branches like HEAD
          next if branch == 'HEAD' || branch =~ /HEAD detached/

          branch
        end.compact.uniq  # Remove nils and duplicates

        # Filter out any empty branch names
        branch_names.reject!(&:empty?)

        # Need at least 3 branches to make interesting questions
        if branch_names.size < 5
          return generate_sample_questions
        end

        branch_names = branch_names.sample(100) if branch_names.size > 100

        branch_names.each do |branch|
          # Get commits for this branch
          branches[branch] = get_commits_for_branch(branch)
        end

        # Generate questions
        questions = []

        self.class.questions_per_round.times do
          # Select branches that have commits
          branch_options = branch_names.sample(4)


          # If we don't have 4 valid branches, pad with duplicates and ensure uniqueness later
          if branch_options.size < 4
            branch_options = branch_names.dup
            while branch_options.size < 4
              branch_options << branch_names.sample
            end
          end

          # Choose a random branch as the correct answer
          correct_branch = branch_options.sample

          # Choose a random commit from this branch
          commit = branches[correct_branch].sample

          # Create the question
          commit_date = commit[:date] #.split(" ")[0..2].join(" ") + " " + commit[:date].split(" ")[4]
          commit_short_sha = commit[:sha][0..6]

          # Format the commit message for display
          message = commit[:message].lines.first&.strip || "No message"
          message = message.length > 50 ? "#{message[0...47]}..." : message

          questions << {
            question: "Which branch was this commit originally made on?\n\n   \"#{message}\"",
            commit_info: "#{commit_short_sha} (by #{commit[:author]} on #{commit_date})",
            options: branch_options.uniq.shuffle,
            correct_answer: correct_branch
          }
        end

        # If we couldn't generate enough questions, fill with sample questions
        if questions.size < self.class.questions_per_round
          sample_questions = generate_sample_questions
          questions += sample_questions[0...(self.class.questions_per_round - questions.size)]
        end

        questions
      rescue => e
        # If any errors occur, fall back to sample questions
        generate_sample_questions
      end
    end

    # Generate sample questions
    def generate_sample_questions
      questions = []

      # Sample data with branch names and commits
      sample_branches = [
        "main", "develop", "feature/user-auth", "bugfix/login",
        "feature/payment", "hotfix/security", "release/v2.0", "staging"
      ]

      # Sample commit data
      sample_commits = [
        { message: "[SAMPLE] Add user authentication flow", author: "Jane Doe", date: "2023-05-15 14:30:22", sha: "a1b2c3d" },
        { message: "[SAMPLE] Fix login page styling issues", author: "John Smith", date: "2023-05-18 10:15:45", sha: "e4f5g6h" },
        { message: "[SAMPLE] Implement password reset functionality", author: "Alice Johnson", date: "2023-05-20 16:45:12", sha: "i7j8k9l" },
        { message: "[SAMPLE] Add payment gateway integration", author: "Bob Brown", date: "2023-05-22 09:20:33", sha: "m2n3o4p" },
        { message: "[SAMPLE] Update README with API documentation", author: "Charlie Davis", date: "2023-05-25 11:05:56", sha: "q5r6s7t" }
      ]

      # Generate sample questions
      self.class.questions_per_round.times do |i|
        # Select a random commit
        commit = sample_commits[i % sample_commits.size]

        # Select 4 random branch names
        branch_options = sample_branches.sample(4)

        # Choose a correct branch
        correct_branch = branch_options.sample

        questions << {
          question: "Which branch was this commit originally made on?\n\n   \"#{commit[:message]}\"",
          commit_info: "#{commit[:sha]} (by #{commit[:author]} on #{commit[:date]})",
          options: branch_options,
          correct_answer: correct_branch
        }
      end

      questions
    end

    def evaluate_answers(question, player_answers)
      results = {}

      player_answers.each do |player_name, answer_data|
        answered = answer_data[:answered] || false
        player_answer = answer_data[:answer]
        time_taken = answer_data[:time_taken] || self.class.question_timeout

        # Check if the answer is correct
        correct = player_answer == question[:correct_answer]

        # Calculate points
        points = 0

        # Base points for correct answer
        if correct
          points = 10

          # Bonus points for fast answers
          if time_taken < 5
            points += 5  # Very fast (under 5 seconds)
          elsif time_taken < 10
            points += 3  # Pretty fast (under 10 seconds)
          elsif time_taken < 12
            points += 1  # Somewhat fast (under 12 seconds)
          end
        end

        # Store the results
        results[player_name] = {
          answer: player_answer,
          correct: correct,
          points: points
        }
      end

      results
    end

    private

    def get_commits_for_branch branch
      unique_commits = []

      # Try different ways to reference the branch
      begin
        # Try a few different ways to reference the branch
        got_commits = false

        # First try as a local branch
        cmd = "cd #{@repo.dir.path} && git log --pretty '#{branch}' --max-count=5 2>/dev/null"
        commit_output = `#{cmd}`

        # Process commits if we found any
        commits = commit_output.split("commit ")[1..-1]

        commits.each do |commit|

          # Extract commit info
          sha = commit.lines[0].split(" ")[0].strip
          author = commit.lines[1].gsub("Author: ", "").split("<")[0].strip
          date = commit.lines[2].gsub("Date: ", "").strip
          message = commit.lines[4..-1].join("\n")

          next unless message.length > 10
          next if message.include?("Merge pull request")
          # Store this commit info
          unique_commits << {
            sha: sha,
            message: message,
            author: author,
            date: date
          }
        end

      rescue => e
        # If we hit any errors with this branch, just skip it
        []
      end

      unique_commits
    end
  end
end
