module GitGameShow
  # Enable this for testing/debugging
  $BLAME_GAME_DEBUG = false

  class BlameGame < MiniGame
    self.name = "Blame Game"
    self.description = "Identify who committed the highlighted line of code! (Can be slow to load)"
    self.example = <<~EXAMPLE
    Who committed the highlighted line of code?

      File: main.rb


          1: def initialize(options = {})
          2:   @logger = options[:logger] || Logger.new(STDOUT)
          3:   @config = load_configuration
        \e[0;33;49m> 4:   @connections = []\e[0m
          5:   @active = false
          6:   setup_signal_handlers
          7: end

      Choose your answer?
      Bob Coder
      Steve Developer
    \e[0;32;49m> Alice Programmer\e[0m
      Sandy Engineer
    EXAMPLE
    self.questions_per_round = 5

    # Custom timing for this mini-game
    def self.question_timeout
      20 # 20 seconds per question (slightly longer than Author Quiz since more code to read)
    end

    def self.question_display_time
      5 # 5 seconds between questions
    end

    def generate_questions(repo)
      questions = []

      # Check if repo exists and has commits
      if repo.nil? || !repo.branches.size.positive?
        puts "No repository with commits found, using sample questions" if $BLAME_GAME_DEBUG
        return generate_sample_questions
      end

      begin
        puts "Starting Blame Game question generation" if $BLAME_GAME_DEBUG
        # Get all files in the repo
        repo_path = repo.dir.path

        # Get a more limited list of files tracked by git
        # 1. Use git ls-files with specific extensions to limit scope
        # 2. Exclude binary files and very large files right from the start
        # 3. Limit to a reasonable number of files to consider
        cmd = "cd #{repo_path} && git ls-files -- '*.rb' '*.js' '*.py' '*.html' '*.css' '*.ts' '*.jsx' '*.tsx' '*.md' '*.yml' '*.yaml' '*.json' '*.c' '*.cpp' '*.h' '*.java' | grep -v -E '\\.min\\.js$|\\.min\\.css$|\\.bundle\\.js$|\\.map$|\\.png$|\\.jpg$|\\.jpeg$|\\.gif$|\\.pdf$|\\.zip$|\\.tar$|\\.gz$|\\.jar$|\\.exe$|\\.bin$' | sort -R | head -100"
        all_files = `#{cmd}`.split("\n").reject(&:empty?)

        puts "Found #{all_files.size} files to choose from for Blame Game" if $BLAME_GAME_DEBUG

        # Skip if no files found
        if all_files.empty?
          puts "No suitable files found in repository, using sample questions" if $BLAME_GAME_DEBUG
          return generate_sample_questions
        end

        # Get all authors in advance to see if we have enough
        all_authors_cmd = "cd #{repo_path} && git log --pretty=format:'%an' | sort | uniq"
        all_authors = `#{all_authors_cmd}`.split("\n").uniq.reject(&:empty?)

        puts "Found #{all_authors.size} unique authors in repository" if $BLAME_GAME_DEBUG

        if all_authors.size < 2
          puts "Not enough authors found (need at least 2), using sample questions" if $BLAME_GAME_DEBUG
          return generate_sample_questions
        end

        # Try to generate the requested number of questions
        # More attempts to increase chances of getting real data
        attempts = 0
        max_attempts = self.class.questions_per_round * 10

        puts "Starting question generation process, will try up to #{max_attempts} attempts" if $BLAME_GAME_DEBUG

        while questions.size < self.class.questions_per_round && attempts < max_attempts
          attempts += 1

          # Select a random file
          file_path = all_files.sample

          # Skip if file path is invalid or file doesn't exist
          full_path = File.join(repo_path, file_path)
          next unless File.exist?(full_path)

          # Skip very large files (over 500 KB)
          next if File.size(full_path) > 500_000

          # Skip binary or non-text files
          begin
            # Test if this file can be read as text
            File.read(full_path, 100).encode('UTF-8', :invalid => :replace, :undef => :replace)
          rescue
            next
          end

          # Skip checking line count, which is slow for large files
          # Instead read the first chunk to estimate if it's large enough
          content_preview = File.read(full_path, 1000) rescue nil
          next unless content_preview

          # Rough estimate if file has enough lines by checking for newlines
          newline_count = content_preview.count("\n")
          next if newline_count < 7

          # Estimate total lines - if preview has enough lines, we can use that section
          if newline_count >= 20
            # Use lines from the preview which we already have
            lines = content_preview.split("\n")
            # Choose a line not too close to the beginning or end
            target_idx = rand(4..(lines.size - 5))
            # Content is just the section we already read, no need to read the whole file
            file_content = lines
            # Target line number is relative to the preview
            target_line_num = target_idx + 1 # 1-based line numbers
            # For display purposes, show the real line number
            target_line_display = target_line_num
          else
            # For small files, do a quick line count
            # This is much faster than counting all lines in a large file
            line_count = content_preview.count("\n") + 1
            file_content = File.readlines(full_path) rescue nil
            next unless file_content
            target_line_num = rand(4..(line_count - 4))
            target_line_display = target_line_num
          end

          # Get git blame for the selected line with better error checking
          # Use a more efficient git blame approach - only get what we need
          begin
            # Extract both the author name and commit date
            blame_cmd = "cd #{repo_path} && git blame -L #{target_line_num},#{target_line_num} --line-porcelain #{file_path}"
            blame_output = `#{blame_cmd}`

            # Extract author name
            author_name_match = blame_output.match(/^author (.+)$/)
            author_name = author_name_match ? author_name_match[1].strip : ""

            # Extract commit date (author-time and author-tz)
            author_time_match = blame_output.match(/^author-time (\d+)$/)
            author_tz_match = blame_output.match(/^author-tz (.+)$/)

            commit_date = nil
            if author_time_match
              timestamp = author_time_match[1].to_i
              commit_date = Time.at(timestamp).strftime("%Y-%m-%d")
            end

            # Skip if we couldn't get a valid author
            if author_name.empty? || author_name.include?("fatal:") || author_name == "Not Committed Yet"
              puts "Skipping uncommitted or invalid line" if $BLAME_GAME_DEBUG
              next
            end

            puts "Found line committed by: #{author_name} on #{commit_date}" if $BLAME_GAME_DEBUG

            # We already have all authors, so we don't need to fetch them again
            # But we should still check if we have enough authors to make this challenging
            if all_authors.size < 4  # Need at least 3 incorrect options + 1 correct
              puts "Not enough unique authors in the repository: #{all_authors.size}" if $BLAME_GAME_DEBUG
              next
            end
          rescue => e
            puts "Error getting blame info: #{e.message}" if $BLAME_GAME_DEBUG
            next
          end

          # Get context lines (3 before, target line, 3 after)
          # Use the content we already read if possible, otherwise read from file
          if newline_count >= 20 && target_idx >= 3 && target_idx <= (lines.size - 4)
            # We can use the lines we already have from the preview
            context_lines = lines[(target_idx-3)..(target_idx+3)]
            start_idx = target_idx - 3
          else
            # Get relevant content directly - much more efficient than reading entire file
            context_cmd = "cd #{repo_path} && tail -n +#{[target_line_num-3, 1].max} #{file_path} | head -7"
            context_output = `#{context_cmd}`
            context_lines = context_output.split("\n")
            start_idx = [target_line_num - 4, 0].max
          end

          next unless context_lines && context_lines.size > 0

          # Add line indicators for display
          display_lines = []
          context_lines.each_with_index do |line, idx|
            line_num = start_idx + idx + 1

            # Mark the target line with > prefix
            prefix = (line_num == target_line_num) ? "> " : "  "

            # Clean the line for display (handle tab characters, trim long lines)
            clean_line = line.gsub("\t", "  ").rstrip
            if clean_line.length > 100
              clean_line = clean_line[0..97] + "..."
            end

            display_lines << "#{prefix}#{line_num}: #{clean_line}"
          end

          # Create context string with file path and highlighted lines
          context = "File: #{file_path}\n\n#{display_lines.join("\n")}"

          # Get incorrect options (other authors)
          incorrect_authors = all_authors.reject { |a| a == author_name }.shuffle.take(3)

          # If we don't have enough distinct authors, generate some
          if incorrect_authors.size < 3
            sample_authors = ["Alice", "Bob", "Charlie", "David", "Emma"].reject { |a| a == author_name }
            incorrect_authors += sample_authors.take(3 - incorrect_authors.size)
          end

          # Create options array with the correct answer and incorrect ones
          all_options = ([author_name] + incorrect_authors).shuffle

          # Create the question with date information
          question_text = "Who committed the highlighted line of code"
          question_text += commit_date ? " on #{commit_date}?" : "?"

          questions << {
            question: question_text,
            context: context,
            options: all_options,
            correct_answer: author_name
          }
        end

      rescue => e
        # Silently fail and use sample questions instead
        return generate_sample_questions
      end

      # Make sure we have enough questions or use fallback
      if questions.size < self.class.questions_per_round
        puts "Could only generate #{questions.size} questions, using sample questions to fill the rest" if $BLAME_GAME_DEBUG
        sample_questions = generate_sample_questions
        # Add enough sample questions to reach the required number
        questions += sample_questions[0...(self.class.questions_per_round - questions.size)]
      end

      puts "Generated #{questions.size} questions for Blame Game" if $BLAME_GAME_DEBUG
      questions
    rescue => e
      puts "Error in BlameGame#generate_questions: #{e.message}\n#{e.backtrace.join("\n")}" if $BLAME_GAME_DEBUG
      generate_sample_questions
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
          time_taken = answer_data[:time_taken] || self.class.question_timeout

          if time_taken < 5
            points += 5
          elsif time_taken < 10
            points += 3
          elsif time_taken < 15
            points += 1
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

    def generate_sample_questions
      # Create sample questions in case the repo doesn't have enough data
      sample_authors = ["Alice", "Bob", "Charlie", "David", "Emma"]
      sample_files = ["main.rb", "utils.js", "config.py", "index.html", "styles.css"]
      # Sample dates for the commits
      sample_dates = ["2024-01-15", "2024-02-20", "2024-03-05", "2024-03-10", "2024-03-11"]

      questions = []

      self.class.questions_per_round.times do |i|
        # Select a random author, file, and date for this sample
        correct_author = sample_authors.sample
        file_name = sample_files.sample
        commit_date = sample_dates.sample

        # Create sample code context
        context_lines = []

        case file_name
        when "main.rb"
          context_lines = [
            "def initialize(options = {})",
            "  @logger = options[:logger] || Logger.new(STDOUT)",
            "  @config = load_configuration",
            "  @connections = []",
            "  @active = false",
            "  setup_signal_handlers",
            "end"
          ]
        when "utils.js"
          context_lines = [
            "function formatDate(date) {",
            "  const day = String(date.getDate()).padStart(2, '0');",
            "  const month = String(date.getMonth() + 1).padStart(2, '0');",
            "  const year = date.getFullYear();",
            "  return `${year}-${month}-${day}`;",
            "  // TODO: Add support for different formats",
            "};"
          ]
        when "config.py"
          context_lines = [
            "class Config:",
            "    DEBUG = False",
            "    TESTING = False",
            "    DATABASE_URI = os.environ.get('DATABASE_URI')",
            "    SECRET_KEY = os.environ.get('SECRET_KEY')",
            "    SESSION_COOKIE_SECURE = True",
            "    TEMPLATES_AUTO_RELOAD = True"
          ]
        when "index.html"
          context_lines = [
            "<header>",
            "  <nav>",
            "    <ul>",
            "      <li><a href=\"/\">Home</a></li>",
            "      <li><a href=\"/about\">About</a></li>",
            "      <li><a href=\"/contact\">Contact</a></li>",
            "    </ul>"
          ]
        when "styles.css"
          context_lines = [
            "body {",
            "  font-family: 'Helvetica', sans-serif;",
            "  line-height: 1.6;",
            "  color: #333;",
            "  margin: 0;",
            "  padding: 20px;",
            "  background-color: #f5f5f5;"
          ]
        end

        # Mark a random line as the target (line 4 is index 3)
        target_idx = 3  # Middle line

        # Add line numbers and indicators
        display_lines = []
        context_lines.each_with_index do |line, idx|
          line_num = idx + 1
          prefix = (idx == target_idx) ? "> " : "  "
          display_lines << "#{prefix}#{line_num}: #{line}"
        end

        # Create context string
        context = "File: #{file_name} (SAMPLE)\n\n#{display_lines.join("\n")}"

        # Get incorrect options (other authors)
        incorrect_authors = sample_authors.reject { |a| a == correct_author }.sample(3)
        all_options = ([correct_author] + incorrect_authors).shuffle

        # Create the sample question with date
        questions << {
          question: "Who committed the highlighted line of code on #{commit_date}? (SAMPLE)",
          context: context,
          options: all_options,
          correct_answer: correct_author
        }
      end

      questions
    end
  end
end
