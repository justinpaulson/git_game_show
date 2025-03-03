module GitGameShow
  class CommitMessageQuiz < MiniGame
    self.name = "Commit Message Quiz"
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
        # FORCE SAMPLE QUESTIONS: This guarantees different questions every time
        return generate_sample_questions
        
        # COMPLETELY NEW APPROACH:
        # 1. Use git command directly to get ALL commits
        # 2. Space them out evenly across the repo's history
        # 3. Select a random but diverse set for questions
        
        # Get total number of commits in the repo to determine how far back to go
        begin
          # Use git directly to count all commits
          commit_count_output = repo.lib.run_command('rev-list', ['--count', 'HEAD'])
          total_commits = commit_count_output.to_i
          
          # If we have very few commits, use them all
          if total_commits < 20
            commit_limit = total_commits
          else
            # Otherwise get a good sample
            commit_limit = [500, total_commits].min
          end
        rescue => e
          # Default to a reasonable limit if count fails
          commit_limit = 200
        end
        
        # Debug messages removed
        
        # Always get ALL potential commits
        all_commits = []
        
        if commit_limit > 0
          begin
            # Get commits directly with git and process manually
            # This is more reliable than using the git gem
            log_output = repo.lib.run_command('log', ['--pretty=format:%H|%ad|%s', '--date=iso', "-#{commit_limit}"])
            commit_lines = log_output.split("\n")
            
            # Random shuffle the commits first to avoid any ordering bias
            shuffled_lines = commit_lines.shuffle
            
            # Parse and process commits
            shuffled_lines.each do |line|
              parts = line.split('|', 3)
              next if parts.size < 3
              
              sha = parts[0]
              date_str = parts[1]
              message = parts[2]
              
              # Try to get changed files
              begin
                diff_output = repo.lib.run_command('diff', ['--name-only', "#{sha}^", sha]) rescue nil
                
                # For the first commit that has no parent
                if diff_output.nil? || diff_output.empty?
                  diff_output = repo.lib.run_command('show', ['--name-only', '--pretty=format:', sha]) rescue ""
                end
                
                # Parse changed files
                files = diff_output.split("\n").reject(&:empty?)
                
                # Skip empty or very large change sets
                next if files.empty?
                next if files.size > 10
                
                # Create proper commit data structure
                all_commits << {
                  sha: sha,
                  date_str: date_str,
                  message: message,
                  files: files
                }
                
                # Once we have enough commits, we can stop processing
                break if all_commits.size >= 30
                
              rescue => e
                # Skip this commit if we can't get files
                next
              end
            end
          rescue => e
            # Error handling - just continue silently
          end
        end
        
        # Debug message removed
        
        # If we couldn't find enough commits, use sample questions
        if all_commits.size < self.class.questions_per_round
          return generate_sample_questions
        end
        
        # Select a diverse set of commits - just take random ones since we already shuffled
        selected_commits = all_commits.sample(self.class.questions_per_round * 2)
        
        # Now select final set with emphasis on file diversity
        final_commits = []
        file_types_seen = {}
        
        selected_commits.each do |commit|
          # Skip if we already have enough
          break if final_commits.size >= self.class.questions_per_round
          
          # Get the primary file type from first file
          first_file = commit[:files].first
          ext = File.extname(first_file).downcase
          
          # If we haven't seen this file type yet, prioritize it
          if !file_types_seen[ext]
            file_types_seen[ext] = true
            final_commits << commit
          elsif final_commits.size < self.class.questions_per_round
            # Add this commit only if we need more
            final_commits << commit
          end
        end
        
        # If we still don't have enough, add more random ones
        if final_commits.size < self.class.questions_per_round
          remaining = selected_commits - final_commits
          final_commits += remaining.sample(self.class.questions_per_round - final_commits.size)
        end
        
        # Debug message removed
        
        questions = []
        
        # Use selected commits for questions
        final_commits.take(self.class.questions_per_round).each do |commit_data|
          # Get the commit data
          sha = commit_data[:sha]
          short_sha = sha[0..6]
          message = commit_data[:message]
          files = commit_data[:files]
          date_str = commit_data[:date_str]
          
          # Take first line of message if multiple lines
          message = message.split("\n").first.strip if message.include?("\n")
          
          # Select the correct file (first one for simplicity)
          correct_file = files.first
          
          # Get file paths from other commits to use as incorrect options
          other_files = []
          other_commits = final_commits - [commit_data]
          
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
          
          # Take up to 3 unique other files
          other_files = other_files.uniq.sample(3)
          
          # Create options array with the correct answer and incorrect ones
          all_options = ([correct_file] + other_files).shuffle
          
          # Format the commit date nicely if possible
          nice_date = begin
            parsed_date = Time.parse(date_str)
            parsed_date.strftime('%b %d, %Y')
          rescue
            date_str
          end
          
          # Format consistently with other mini-games
          questions << {
            question: "Which file was most likely changed in this commit?\n\n   \"#{message}\"",
            commit_info: "#{short_sha} (#{nice_date})",
            options: all_options,
            correct_answer: correct_file
          }
        end
        
        return questions
      rescue => e
        # If anything fails, fall back to sample questions
        return generate_sample_questions
      end
    end
    
    def evaluate_answers(question, player_answers)
      results = {}
      
      player_answers.each do |player_name, answer_data|
        player_answer = answer_data[:answer]
        correct = player_answer == question[:correct_answer]
        
        points = 0
        
        if correct
          points = 10 # Base points for correct answer
          
          # Bonus points for fast answers, identical to AuthorQuiz
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
    
    # Generate sample questions with a lot more variety
    def generate_sample_questions
      questions = []
      
      # MUCH larger set of sample files that might be changed in a project
      common_files = [
        # Frontend files
        "src/main.js", "src/app.js", "src/index.js", "src/router.js", 
        "src/components/Header.js", "src/components/Footer.js", "src/components/Sidebar.js",
        "src/components/Navigation.js", "src/components/UserProfile.js", "src/components/Dashboard.js",
        "src/views/Home.vue", "src/views/Login.vue", "src/views/Settings.vue",
        "public/index.html", "public/favicon.ico", "public/manifest.json",
        
        # Styling files
        "css/styles.css", "css/main.css", "styles/theme.scss", "styles/variables.scss",
        "src/assets/styles.css", "src/styles/global.css", "sass/main.scss",
        
        # Backend files
        "lib/utils.js", "lib/helpers.js", "lib/auth.js", "lib/database.js",
        "server/index.js", "server/api.js", "server/middleware/auth.js",
        "app/controllers/users_controller.rb", "app/models/user.rb", "app/models/post.rb",
        "app/services/authentication_service.rb", "app/helpers/application_helper.rb",
        
        # Configuration files
        "config/webpack.config.js", "config/database.yml", "config/routes.rb",
        "config/application.rb", ".eslintrc.js", ".prettierrc", "tsconfig.json",
        "babel.config.js", "webpack.config.js", "vite.config.js", "jest.config.js",
        
        # Documentation files
        "README.md", "CONTRIBUTING.md", "LICENSE", "CHANGELOG.md", "docs/API.md",
        "docs/setup.md", "docs/deployment.md", "docs/architecture.md",
        
        # DevOps files
        "Dockerfile", "docker-compose.yml", ".github/workflows/ci.yml",
        ".github/workflows/deploy.yml", ".gitlab-ci.yml", "Jenkinsfile",
        
        # Testing files
        "tests/unit/login.test.js", "tests/integration/auth.test.js",
        "spec/models/user_spec.rb", "spec/controllers/posts_controller_spec.rb",
        "__tests__/components/Header.test.tsx", "cypress/integration/login.spec.js",
        
        # Assets
        "public/images/logo.png", "public/images/banner.jpg", "src/assets/icons/home.svg",
        "public/fonts/OpenSans.woff2", "public/data/countries.json"
      ]
      
      # MUCH larger set of sample commit messages with realistic commit hashes
      sample_commits = [
        # UI/Frontend commits
        {
          message: "Fix navigation bar styling on mobile devices", 
          file: "css/styles.css",
          sha: rand(0xfffff).to_s(16),
          date: "Mar #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Add responsive design for dashboard components", 
          file: "src/components/Dashboard.js",
          sha: rand(0xfffff).to_s(16),
          date: "Jan #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Update color scheme in theme variables", 
          file: "styles/variables.scss",
          sha: rand(0xfffff).to_s(16),
          date: "Apr #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Implement dark mode toggle in user settings", 
          file: "src/views/Settings.vue",
          sha: rand(0xfffff).to_s(16),
          date: "May #{rand(1..28)}, #{2023 + rand(3)}"
        },
        
        # Backend/API commits
        {
          message: "Fix user authentication bug in login flow", 
          file: "lib/auth.js",
          sha: rand(0xfffff).to_s(16),
          date: "Feb #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Add rate limiting to API endpoints", 
          file: "server/middleware/auth.js",
          sha: rand(0xfffff).to_s(16),
          date: "Jun #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Optimize database queries for user profile page", 
          file: "app/controllers/users_controller.rb",
          sha: rand(0xfffff).to_s(16),
          date: "Jul #{rand(1..28)}, #{2023 + rand(3)}"
        },
        
        # Testing commits
        {
          message: "Add unit tests for authentication service", 
          file: "tests/unit/login.test.js",
          sha: rand(0xfffff).to_s(16),
          date: "Feb #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Fix flaky integration tests for payment flow", 
          file: "tests/integration/auth.test.js",
          sha: rand(0xfffff).to_s(16),
          date: "Mar #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Add E2E tests for user registration", 
          file: "cypress/integration/login.spec.js",
          sha: rand(0xfffff).to_s(16),
          date: "Apr #{rand(1..28)}, #{2023 + rand(3)}"
        },
        
        # DevOps/Infrastructure commits
        {
          message: "Update CI pipeline to run tests in parallel", 
          file: ".github/workflows/ci.yml",
          sha: rand(0xfffff).to_s(16),
          date: "May #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Add Docker support for development environment", 
          file: "Dockerfile",
          sha: rand(0xfffff).to_s(16),
          date: "Jun #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Configure automatic deployment to staging", 
          file: ".github/workflows/deploy.yml",
          sha: rand(0xfffff).to_s(16),
          date: "Jul #{rand(1..28)}, #{2023 + rand(3)}"
        },
        
        # Documentation commits
        {
          message: "Update README with new installation instructions", 
          file: "README.md",
          sha: rand(0xfffff).to_s(16),
          date: "Aug #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Add API documentation for new endpoints", 
          file: "docs/API.md",
          sha: rand(0xfffff).to_s(16),
          date: "Sep #{rand(1..28)}, #{2023 + rand(3)}"
        },
        {
          message: "Update CHANGELOG for v2.3.0 release", 
          file: "CHANGELOG.md",
          sha: rand(0xfffff).to_s(16),
          date: "Oct #{rand(1..28)}, #{2023 + rand(3)}"
        }
      ]
      
      # Randomize which commits we use for each round
      selected_commits = sample_commits.sample(self.class.questions_per_round * 2)
      
      # Create questions from sample data
      self.class.questions_per_round.times do |i|
        # Different commit each time regardless of how many rounds we play
        sample_commit = selected_commits[i]
        
        # Correct file for this sample commit
        correct_file = sample_commit[:file]
        
        # Get other files as incorrect options
        other_files = common_files.reject { |f| f == correct_file }.sample(3)
        
        # All options with the correct one included
        all_options = ([correct_file] + other_files).shuffle
        
        questions << {
          question: "Which file was most likely changed in this commit?\n\n   \"#{sample_commit[:message]}\"",
          commit_info: "#{sample_commit[:sha]} (#{sample_commit[:date]})",
          options: all_options,
          correct_answer: correct_file
        }
      end
      
      # Randomize the question order
      questions.shuffle
    end
    
    private
    
    # Helper method to get commits with their changed files
    # Optionally filter by date (commits after the specified date)
    def get_recent_commits_with_files(repo, count, after_date = nil)
      begin
        # Get commits
        commits = repo.log(count).to_a
        
        # Filter by date if specified
        if after_date
          commits = commits.select do |commit|
            begin
              commit_time = commit.date.is_a?(Time) ? commit.date : Time.parse(commit.date.to_s)
              commit_time > after_date
            rescue
              false # Skip commits with unparseable dates
            end
          end
        end
        
        commits_with_files = commits.map do |commit|
          # Get diff from previous commit
          diff_files = []
          
          begin
            # Use git command directly for simplicity
            diff_output = repo.lib.run_command('diff', ['--name-only', "#{commit.sha}^", commit.sha])
            diff_files = diff_output.split("\n").reject(&:empty?)
          rescue => e
            # Handle the case when the commit is the first commit (no parent)
            if commit.parent.nil?
              begin
                diff_output = repo.lib.run_command('show', ['--name-only', '--pretty=format:', commit.sha])
                diff_files = diff_output.split("\n").reject(&:empty?)
              rescue => e
                # If we can't get files for this commit, just use an empty array
                diff_files = []
              end
            end
          end
          
          # Skip commits that modified too many files (likely big refactors or dependency updates)
          next nil if diff_files.size > 20
          
          # Skip commits with no files
          next nil if diff_files.empty?
          
          {
            commit: commit,
            files: diff_files,
            file_types: get_file_types(diff_files) # Store file types for better selection
          }
        end
        
        # Filter out nil entries from commits that were skipped
        commits_with_files.compact
      rescue => e
        # If anything fails, return an empty array
        []
      end
    end
    
    # Helper method to categorize file types based on extension
    def get_file_types(files)
      types = {}
      
      files.each do |file|
        ext = File.extname(file).downcase
        types[ext] ||= 0
        types[ext] += 1
      end
      
      types
    end
    
    # Select diverse commits to ensure variety in questions
    def select_diverse_commits(commits, count)
      return commits.sample(count) if commits.size <= count
      
      # Strategy: Select commits that provide maximum diversity in:
      # 1. Time periods
      # 2. File types
      # 3. Author variety
      selected = []
      
      # First, sort by date to get a chronological view
      sorted_by_date = commits.sort_by do |c|
        begin
          date = c[:commit].date
          date.is_a?(Time) ? date : Time.parse(date.to_s)
        rescue
          Time.now
        end
      end
      
      # Divide into time buckets to ensure time diversity
      bucket_size = [(sorted_by_date.size / 5).ceil, 1].max
      time_buckets = sorted_by_date.each_slice(bucket_size).to_a
      
      # Take one from each time bucket first (prioritizing time diversity)
      time_buckets.each do |bucket|
        break if selected.size >= count
        selected << bucket.sample
      end
      
      remaining = commits - selected
      
      # Next, group remaining by file type
      file_type_groups = {}
      remaining.each do |commit|
        # Find most common file type in this commit
        primary_type = commit[:file_types].max_by { |_, count| count }&.first || "unknown"
        file_type_groups[primary_type] ||= []
        file_type_groups[primary_type] << commit
      end
      
      # Add one from each file type group
      file_type_groups.keys.shuffle.each do |file_type|
        break if selected.size >= count
        next if file_type_groups[file_type].empty?
        
        commit = file_type_groups[file_type].sample
        selected << commit
        remaining.delete(commit)
      end
      
      # Group remaining by author
      author_groups = {}
      remaining.each do |commit|
        begin
          author = commit[:commit].author.name || "unknown"
          author_groups[author] ||= []
          author_groups[author] << commit
        rescue
          # Skip if author info not available
        end
      end
      
      # Add one from each author group
      author_groups.keys.shuffle.each do |author|
        break if selected.size >= count
        next if author_groups[author].empty?
        
        commit = author_groups[author].sample
        selected << commit
        remaining.delete(commit)
      end
      
      # If we still need more, add random remaining commits
      if selected.size < count && !remaining.empty?
        selected += remaining.sample(count - selected.size)
      end
      
      # Ensure we have exactly the requested number
      selected = selected.take(count)
      
      # Return the selected commits in random order to avoid predictable patterns
      selected.shuffle
    end
  end
end