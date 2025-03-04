require_relative 'lib/git_game_show/version'

Gem::Specification.new do |spec|
  spec.name          = "git_game_show"
  spec.version       = GitGameShow::VERSION
  spec.authors       = ["Justin Paulson"]
  spec.email         = ["justinapaulson@gmail.com"]

  spec.summary       = "A fun interactive multiplayer game based on Git trivia"
  spec.description   = "Git Game Show is a multiplayer game that tests your team's knowledge of Git with various mini-games like author quizzes, commit message quizzes, and more."
  spec.homepage      = "https://github.com/justinpaulson/git_game_show"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.glob('{bin,lib,mini_games}/**/*') + ['LICENSE', 'README.md']
  spec.bindir        = "bin"
  spec.executables   = ["git-game-show"]
  spec.require_paths = ["lib"]
  
  # Ensure the executable has proper permissions
  File.chmod(0755, 'bin/git-game-show') if File.exist?('bin/git-game-show')

  # Dependencies
  spec.add_dependency "thor", "~> 1.2"
  spec.add_dependency "colorize", "~> 0.8"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "eventmachine", "~> 1.2"
  spec.add_dependency "websocket-client-simple", "~> 0.6"
  spec.add_dependency "websocket-eventmachine-server", "~> 1.0"
  spec.add_dependency "git", "~> 1.13"
  spec.add_dependency "clipboard", "~> 1.3"  # Make sure this is included for clipboard functionality
  spec.add_dependency "rubyzip", "~> 2.3"    # For auto-installing ngrok

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
end
