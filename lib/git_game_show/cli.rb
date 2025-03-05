require 'uri'

module GitGameShow
  class CLI < Thor
    map %w[--version -v] => :version

    desc 'version', 'Display Git Game Show version'
    def version
      puts "Git Game Show version #{GitGameShow::VERSION}"

      # Check for updates if the Updater class exists
      GitGameShow::Updater.check_for_updates if defined?(GitGameShow::Updater)
    end

    desc '', 'Show welcome screen'
    def welcome
      display_welcome_screen

      # Check for updates if the Updater class exists
      GitGameShow::Updater.check_for_updates if defined?(GitGameShow::Updater)

      prompt = TTY::Prompt.new
      choice = prompt.select("", [
        {name: "Host a new game", value: :host},
        {name: "Join a game", value: :join},
        {name: "Check for updates", value: :update},
        {name: "Exit", value: :exit}
      ])

      case choice
      when :host
        prompt_for_host_options
      when :join
        prompt_for_join_options
      when :update
        if defined?(GitGameShow::Updater)
          # Force check for updates
          current_version = GitGameShow::VERSION
          puts "Current version: #{current_version}"
          puts "Checking for updates..."

          latest_version = GitGameShow::Updater.send(:fetch_latest_version)
          if latest_version.nil?
            puts "Unable to connect to RubyGems.org. Please check your internet connection."
          elsif GitGameShow::Updater.send(:newer_version_available?, current_version, latest_version)
            GitGameShow::Updater.send(:display_update_prompt, current_version, latest_version)
          else
            puts "✓ You already have the latest version (#{current_version})!".colorize(:green)
          end

          # Return to welcome screen after checking
          welcome
        else
          puts "Update feature not available. Please update manually with 'gem update git_game_show'."
          welcome
        end
      when :exit
        puts "Thanks for playing Git Game Show!"
        exit(0)
      end
    end

    desc 'host [OPTIONS]', 'Host a new game session'
    method_option :port, type: :numeric, default: GitGameShow::DEFAULT_CONFIG[:internal_port],
                  desc: 'Port to run the server on'
    method_option :password, type: :string,
                  desc: 'Optional password for players to join (auto-generated if not provided)'
    method_option :rounds, type: :numeric, default: GitGameShow::DEFAULT_CONFIG[:rounds],
                  desc: 'Number of rounds to play'
    method_option :repo_path, type: :string, default: '.',
                  desc: 'Path to git repository'
    def host
      begin
        # Validate git repository
        repo = Git.open(options[:repo_path])

        # Generate a random password if not provided
        password = options[:password] || generate_random_password

        # Start the game server
        server = GameServer.new(
          port: options[:port],
          password: password,
          rounds: options[:rounds],
          repo: repo
        )

        # Get IP addresses before clearing screen
        # Get the local IP address for players to connect to
        local_ip = `hostname -I 2>/dev/null || ipconfig getifaddr en0 2>/dev/null`.strip

        # Get external IP address using a public service
        puts "Detecting your external IP address... (this will only take a second)"
        begin
          # Try multiple services in case one is down
          external_ip = `curl -s --connect-timeout 3 https://api.ipify.org || curl -s --connect-timeout 3 https://ifconfig.me || curl -s --connect-timeout 3 https://icanhazip.com`.strip
          external_ip = nil if external_ip.empty? || external_ip.length > 45 # Sanity check
        rescue
          external_ip = nil
        end

        # Clear the screen
        display_ggs

        # Ask user which IP to use
        prompt = TTY::Prompt.new
        ip_choices = []
        ip_choices << {name: "Local IP (#{local_ip})", value: {:type => :local, :ip => local_ip}} if !local_ip.empty?
        ip_choices << {name: "External IP (#{external_ip})", value: {:type => :external, :ip => external_ip}} if external_ip
        ip_choices << {name: "Automatic tunneling", value: {:type => :tunnel}}
        ip_choices << {name: "Custom IP or hostname", value: {:type => :custom}}

        # Format question with explanation
        display_info_box(:info, "Network Setup", [
          "  • Local IP: Only for players on the same network",
          "  • External IP: For internet players",
          "      - requires router port forwarding",
          "  • Automatic tunneling: For internet players",
          "      - requires free account & authorization through ngrok",
          "  • Custom IP: For advanced users with specific network setup"
        ])

        ip_choice = prompt.select("How should players connect to your game?", ip_choices)

        # Handle different connection options
        external_port = options[:port] || GitGameShow::DEFAULT_CONFIG[:internal_port]
        case ip_choice[:type]
        when :local, :external
          ip = ip_choice[:ip]
        when :custom
          ip = prompt.ask("Enter your IP address or hostname:", required: true)
        when :tunnel
          # Clear the screen and show informative message about ngrok
          display_ggs
          display_info_box(:info, "Ngrok Tunnel Setup", [
            " The automatic tunneling option uses ngrok, a secure tunneling service.",
            " This will allow players to connect from anywhere without port forwarding.",
            "                                                                            ",
            " If you do not already have ngrok set up:",
            " • The ngrok client will be downloaded and started automatically",
            " • Instructions will be provided to set up a required free account on ngrok",
            " • The tunnel will be established and the game will start"
          ])

          # Check if ngrok is available
          begin
            # First, try to find if ngrok command is available
            ngrok_available = system("which ngrok > /dev/null 2>&1") || system("where ngrok > /dev/null 2>&1")

            unless ngrok_available
              # Offer to install ngrok automatically
              prompt = TTY::Prompt.new
              install_ngrok = prompt.yes?("Ngrok is required for tunneling but wasn't found. Would you like to install it now?")

              if install_ngrok
                puts "Installing ngrok..."

                # Determine platform and architecture
                os = RbConfig::CONFIG['host_os']
                arch = RbConfig::CONFIG['host_cpu']

                # Default to 64-bit
                arch_suffix = arch =~ /64|amd64/ ? '64' : '32'

                # Determine the download URL based on OS
                download_url = if os =~ /darwin/i
                                 "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-#{arch =~ /arm|aarch64/ ? 'arm64' : 'amd64'}.zip"
                               elsif os =~ /linux/i
                                 "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-#{arch =~ /arm|aarch64/ ? 'arm64' : 'amd64'}.zip"
                               elsif os =~ /mswin|mingw|cygwin/i
                                 "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-#{arch_suffix}.zip"
                               else
                                 nil
                               end

                if download_url.nil?
                  puts "Could not determine your system type. Please install ngrok manually from https://ngrok.com/download"
                  exit(1)
                end

                # Determine installation directory in user's home folder
                user_home = ENV['HOME'] || ENV['USERPROFILE']
                install_dir = File.join(user_home, '.git_game_show')
                FileUtils.mkdir_p(install_dir) unless Dir.exist?(install_dir)

                # Download ngrok
                puts "Downloading ngrok from #{download_url}..."
                require 'open-uri'
                require 'tempfile'

                temp_zip = Tempfile.new(['ngrok', '.zip'])
                temp_zip.binmode

                begin
                  URI.open(download_url) do |remote_file|
                    temp_zip.write(remote_file.read)
                  end
                  temp_zip.close

                  # Extract zip
                  require 'zip'
                  puts "Extracting ngrok..."

                  Zip::File.open(temp_zip.path) do |zip_file|
                    zip_file.each do |entry|
                      entry_path = File.join(install_dir, entry.name)
                      entry.extract(entry_path) { true } # Overwrite if exists
                      FileUtils.chmod(0755, entry_path) if entry.name == 'ngrok' || entry.name == 'ngrok.exe'
                    end
                  end

                  # Add to PATH for the current process
                  ENV['PATH'] = "#{install_dir}:#{ENV['PATH']}"

                  # Check if installation was successful
                  ngrok_path = File.join(install_dir, os =~ /mswin|mingw|cygwin/i ? 'ngrok.exe' : 'ngrok')
                  if File.exist?(ngrok_path)
                    puts "Ngrok installed successfully to #{install_dir}"
                    ngrok_available = true

                    # Add a hint about adding to PATH permanently
                    puts "\nTIP: To use ngrok in other terminal sessions, add this to your shell profile:"
                    puts "export PATH=\"#{install_dir}:$PATH\""
                    puts "\nPress Enter to continue..."
                    gets
                  else
                    puts "Failed to install ngrok. Please install manually from https://ngrok.com/download"
                    exit(1)
                  end
                rescue => e
                  puts "Error installing ngrok: #{e.message}"
                  puts "Please install manually from https://ngrok.com/download"
                  exit(1)
                ensure
                  temp_zip.unlink
                end
              else
                # User opted not to install
                puts "Ngrok installation declined. Please choose a different connection option."
                exit(1)
              end
            end

            puts "Starting tunnel service... (this may take a few moments)"

            # Start ngrok in non-blocking mode for the specified port
            require 'open3'
            require 'json'

            # Kill any existing ngrok processes
            system("pkill -f ngrok > /dev/null 2>&1 || taskkill /F /IM ngrok.exe > /dev/null 2>&1")

            # Check for ngrok api availability first (might be a previous instance running)
            puts "Checking for existing ngrok sessions..."
            api_available = system("curl -s http://localhost:4040/api/tunnels > /dev/null 2>&1")

            if api_available
              puts "Found existing ngrok session. Attempting to use it or restart if needed..."
              # Try to kill it to start fresh
              system("pkill -f ngrok > /dev/null 2>&1 || taskkill /F /IM ngrok.exe > /dev/null 2>&1")
              # Give it a moment to shut down
              sleep(1)
            end

            # Check for ngrok auth status
            puts "Checking ngrok authentication status..."

            # Check if the user has authenticated with ngrok
            auth_check = `ngrok config check 2>&1`
            auth_needed = auth_check.include?("auth") || auth_check.include?("authtoken") || auth_check.include?("ERR") || auth_check.include?("error")

            if auth_needed
              display_ggs
              display_info_box(:info, 'Ngrok Authorization Required', [
                " Starting with ngrok v3, you need to create a free account and authorize      ",
                " to use TCP tunnels. This is a one-time setup.                                ",
                "                                                                              ",
                " Steps to authorize ngrok:                                                    ",
                "  1. Create a free account at https://ngrok.com/signup                        ",
                "  2. Get an authtoken https://dashboard.ngrok.com/get-started/your-authtoken  ",
                "  3. Enter your authtoken below                                               "
              ])
              puts ""

              prompt = TTY::Prompt.new
              token = prompt.mask("Enter your ngrok authtoken:")

              if token && !token.empty?
                puts "Setting up ngrok authentication..."
                auth_result = system("ngrok config add-authtoken #{token}")

                if !auth_result
                  puts "Failed to set ngrok authtoken. Please try again manually with:"
                  puts "  ngrok config add-authtoken YOUR_TOKEN"
                  puts ""
                  puts "Press Enter to continue with local IP instead..."
                  gets
                  ip = local_ip
                  return
                else
                  puts "Successfully authenticated with ngrok!"
                end
              else
                puts "No token provided. Falling back to local IP."
                puts "Press Enter to continue..."
                gets
                ip = local_ip
                return
              end
            end

            # Start ngrok with enhanced options
            puts "Starting ngrok tunnel for port #{options[:port]}..."
            stdin, stdout, stderr, wait_thr = Open3.popen3("ngrok tcp #{options[:port]} --log=stdout")

            # Capture the stderr from ngrok to check for common errors
            err_thread = Thread.new do
              while (error_line = stderr.gets)
                if error_line.include?("ERR") || error_line.include?("error")
                  if error_line.include?("auth") || error_line.include?("authtoken")
                    puts "\nAuthentication error detected: #{error_line.strip}"
                  elsif error_line.include?("connection")
                    puts "\nConnection error detected: #{error_line.strip}"
                  elsif error_line.include?("bind") || error_line.include?("address already in use")
                    puts "\nPort binding error detected: #{error_line.strip}"
                  else
                    puts "\nngrok error: #{error_line.strip}"
                  end
                end
              end
            end

            # Wait for ngrok to start and get the URL
            puts "Waiting for tunnel to be established (this may take up to 30 seconds)..."
            tunnel_url = nil
            30.times do |attempt|
              # Visual feedback for long wait times
              print "." if attempt > 0 && attempt % 5 == 0

              # Check if we can query the ngrok API
              status = Open3.capture2("curl -s http://localhost:4040/api/tunnels")
              if status[1].success? # If API is available
                tunnels = JSON.parse(status[0])['tunnels']
                if tunnels && !tunnels.empty?
                  tunnel = tunnels.first
                  # Get the tunnel URL - it should be a tcp URL with format tcp://x.x.x.x:port
                  public_url = tunnel['public_url']
                  if public_url && public_url.start_with?('tcp://')
                    # Extract the host and port
                    public_url = public_url.sub('tcp://', '')
                    host, port = public_url.split(':')

                    # Use the host with the ngrok-assigned port
                    ip = host
                    # Create a new port variable instead of modifying the frozen options hash
                    external_port = port.to_i

                    tunnel_url = public_url

                    # Save the process ID for later cleanup
                    at_exit do
                      system("pkill -f ngrok > /dev/null 2>&1 || taskkill /F /IM ngrok.exe > /dev/null 2>&1")
                    end

                    display_ggs

                    # We need to handle the colorized content within the green box
                    content = [
                      " Your game is now accessible over the internet",
                      " The ngrok tunnel is running in the background:",
                      "                                                                            ",
                      "   ngrok ip:         #{ip.ljust(57)}".colorize(:light_blue),
                      "   ngrok port:       #{external_port.to_s.ljust(57)}".colorize(:light_blue),
                      "   ngrok public URL: #{public_url.ljust(57)}".colorize(:light_blue),
                      "                                                                            ",
                      " DO NOT close the terminal window until your game is finished",
                      " The tunnel will automatically close when you exit the game"
                    ]

                    display_info_box(:success, 'Ngrok tunnel established successfully!', content)
                    puts ""
                    puts "Press Enter to continue..."
                    gets

                    break
                  end
                end
              end
              sleep 1
            end

            unless tunnel_url
              display_ggs
              display_info_box(:error, 'Tunnel setup failed!', [
                " ngrok tunnel could not be established",
                " Most common reason: Missing or invalid ngrok authentication token",
                " Falling back to local IP (players will only be able to join locally)",
                "                                                                            ",
                " Common solutions:",
                "  1. Create a free account at https://ngrok.com/signup",
                "  2. Get an authtoken https://dashboard.ngrok.com/get-started/your-authtoken",
                "  3. Run this command: ngrok config add-authtoken <YOUR_TOKEN>",
                "  4. Then restart the game and try tunneling again"
              ])
              puts "Press Enter to continue with local IP..."
              gets

              ip = local_ip
            end
          rescue => e
            display_ggs
            display_info_box(:error, 'Error setting up ngrok tunnel!', [
              " An error occurred while trying to set up the ngrok tunnel",
              " This is likely an authentication issue with ngrok",
              " Falling back to local IP (players will only be able to join locally)"
            ])
            puts "Error details: #{e.message}"
            puts ""
            puts "Press Enter to continue with local IP..."
            gets

            ip = local_ip
          end
        end

        # Now ask for the port (after network setup is complete)
        # Skip if ngrok assigned a port already
        unless ip_choice[:type] == :tunnel
          internal_port = prompt.ask("Which port would you like to use?",
                            convert: :int,
                            default: GitGameShow::DEFAULT_CONFIG[:internal_port])

          # Update the server's port
          server.instance_variable_set(:@port, internal_port)
        end

        secure_link = "gitgame://#{ip}:#{external_port}/#{URI.encode_www_form_component(password)}"

        # Start the server with the improved UI and pass the join link
        server.start_with_ui(secure_link)

      rescue Git::GitExecuteError
        puts "Error: Not a valid Git repository at #{options[:repo_path]}".colorize(:red)
      rescue => e
        puts "Error: #{e.message}".colorize(:red)
      end
    end

    desc 'join SECURE_LINK', 'Join an existing game session using a secure link'
    method_option :name, type: :string, desc: 'Your player name'
    def join(secure_link)
      begin
        # Check if we need to prompt for a name
        name = options[:name]

        # Parse the secure link
        if secure_link.start_with?('gitgame://')
          uri = URI.parse(secure_link.sub('gitgame://', 'http://'))
          host = uri.host
          port = uri.port || GitGameShow::DEFAULT_CONFIG[:internal_port]
          password = URI.decode_www_form_component(uri.path.sub('/', ''))

          # Check if this is a secure (ngrok) connection from query params
          is_secure = !uri.query.nil? && uri.query.include?('secure=')
        else
          # Legacy format - assume it's host:port
          host, port = secure_link.split(':')
          port ||= GitGameShow::DEFAULT_CONFIG[:internal_port]
          password = options[:password]
          is_secure = false

          # If no password provided in legacy format, ask for it
          unless password
            prompt = TTY::Prompt.new
            password = prompt.mask("Enter the game password:")
          end
        end

        # If no name provided, ask for it
        unless name
          prompt = TTY::Prompt.new
          name = prompt.ask("Enter your name:") do |q|
            q.required true
          end
        end

        # Create player client
        client = PlayerClient.new(
          host: host,
          port: port.to_i,
          password: password,
          name: name,
          secure: is_secure
        )

        puts "=== Git Game Show Client ===".colorize(:green)
        puts "Connecting to game at #{host}:#{port}".colorize(:light_blue)

        # Connect to the game
        client.connect

      rescue => e
        puts "Error: #{e.message}".colorize(:red)
      end
    end

    default_task :welcome

    private

    def display_ggs
      clear_screen
      lines = [
        " ██████╗ ".colorize(:red) + "  ██████╗ ".colorize(:green) + "  █████╗".colorize(:blue),
        "██╔════╝ ".colorize(:red) + " ██╔════╝ ".colorize(:green) + " ██╔═══╝".colorize(:blue),
        "██║  ███╗".colorize(:red) + " ██║  ███╗".colorize(:green) + " ███████╗".colorize(:blue),
        "██║   ██║".colorize(:red) + " ██║   ██║".colorize(:green) + " ╚════██║".colorize(:blue),
        "╚██████╔╝".colorize(:red) + " ╚██████╔╝".colorize(:green) + " ██████╔╝".colorize(:blue),
        " ╚═════╝ ".colorize(:red) + "  ╚═════╝ ".colorize(:green) + " ╚═════╝ ".colorize(:blue),
      ]
      lines.each { |line| puts line.center(120) }
    end

    def display_game_logo
      clear_screen
      puts (" ██████╗ ██╗████████╗".colorize(:red) + "     ██████╗  █████╗ ███╗   ███╗███████╗".colorize(:green)).center(110)
      puts ("██╔════╝ ██║╚══██╔══╝".colorize(:red) + "    ██╔════╝ ██╔══██╗████╗ ████║██╔════╝".colorize(:green)).center(110)
      puts ("██║  ███╗██║   ██║   ".colorize(:red) + "    ██║  ███╗███████║██╔████╔██║█████╗  ".colorize(:green)).center(110)
      puts ("██║   ██║██║   ██║   ".colorize(:red) + "    ██║   ██║██╔══██║██║╚██╔╝██║██╔══╝  ".colorize(:green)).center(110)
      puts ("╚██████╔╝██║   ██║   ".colorize(:red) + "    ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗".colorize(:green)).center(110)
      puts (" ╚═════╝ ╚═╝   ╚═╝   ".colorize(:red) + "     ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝".colorize(:green)).center(110)

      puts (" █████╗ ██╗  ██╗ ██████╗ ██╗    ██╗".colorize(:blue)).center(95)
      puts ("██╔═══╝ ██║  ██║██╔═══██╗██║    ██║".colorize(:blue)).center(95)
      puts ("███████╗███████║██║   ██║██║ █╗ ██║".colorize(:blue)).center(95)
      puts ("╚════██║██╔══██║██║   ██║██║███╗██║".colorize(:blue)).center(95)
      puts ("██████╔╝██║  ██║╚██████╔╝╚███╔███╔╝".colorize(:blue)).center(95)
      puts ("╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝ ".colorize(:blue)).center(95)
    end

    def display_welcome_screen
      display_game_logo
      puts ""
      display_info_box(:info, "Welcome to Git Game Show! version " + GitGameShow::VERSION, [
        " Test your team's knowledge with fun mini games based on git commit history.",
        "",
        " Choose to host a new game or join an existing one."
      ])
    end

  def prompt_for_host_options
    prompt = TTY::Prompt.new

    repo_path = prompt.ask("Enter the path to the Git repository (leave empty for current directory):", default: '.')
    rounds = prompt.ask("How many rounds would you like to play? (1-10)",
                       convert: :int,
                       default: GitGameShow::DEFAULT_CONFIG[:rounds]) do |q|
      q.validate(/^([1-9]|10)$/, "Please enter a number between 1 and 10")
    end

    # Call the host method with the provided options (password will be auto-generated)
    # Port will be asked after network setup
    invoke :host, [], {
      repo_path: repo_path,
      rounds: rounds
    }
  end

    def prompt_for_join_options
      prompt = TTY::Prompt.new

      secure_link = prompt.ask("Paste the join link provided by the host:")
      name = prompt.ask("Enter your name:")

      # Call the join method with the provided options
      invoke :join, [secure_link], {
        name: name
      }
    end

    def clear_screen
      system('clear') || system('cls')
    end

    def generate_random_password
      # Generate a simple but memorable password: adjective-noun-number
      adjectives = %w[happy quick brave clever funny orange purple blue green golden shiny lucky awesome mighty rapid swift]
      nouns = %w[dog cat fox tiger panda bear whale shark lion wolf dragon eagle falcon rocket ship star planet moon river mountain]

      "#{adjectives.sample}-#{nouns.sample}-#{rand(100..999)}"
    end

    def display_info_box(kind, heading, content, width = 80)
      # Set color based on the kind of box
      color = case kind.to_sym
              when :info
                :light_blue
              when :success
                :green
              when :error
                :red
              else
                :light_blue
              end

      # Calculate border width - using 78 as in existing boxes
      content_width = width - 2

      # Create the box with borders and heading in the specified color
      puts ("╭" + "─" * content_width + "╮").colorize(color)
      puts "│#{heading.center(content_width)}│".colorize(color)
      puts ("├" + "─" * content_width + "┤").colorize(color)

      # Split content by lines and format each line
      if content.is_a?(String)
        content.each_line do |line|
          puts "│".colorize(color) + "#{line.chomp}".ljust(content_width) + "│".colorize(color)
        end
      elsif content.is_a?(Array)
        content.each do |line|
          puts "│".colorize(color) + "#{line}".ljust(content_width) + "│".colorize(color)
        end
      end

      puts ("╰" + "─" * content_width + "╯").colorize(color)
      puts ""
    end
  end
end
