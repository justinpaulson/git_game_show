require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

# Set executable bit before building
Rake::Task["build"].enhance [:ensure_executable_permissions]

desc "Ensure executable permissions are set"
task :ensure_executable_permissions do
  puts "Setting executable permissions for git-game-show..."
  executable_path = File.join(File.dirname(__FILE__), 'bin', 'git-game-show')
  File.chmod(0755, executable_path) if File.exist?(executable_path)
end

desc "Build and install the gem locally"
task :local_install => :build do
  sh "gem install pkg/git_game_show-#{GitGameShow::VERSION}.gem"
end

desc "Show a list of all tasks"
task :tasks do
  puts "Available tasks:"
  puts "rake build            # Build git_game_show-#{GitGameShow::VERSION}.gem into the pkg directory"
  puts "rake install          # Build and install git_game_show-#{GitGameShow::VERSION}.gem into system gems"
  puts "rake local_install    # Build and install the gem locally"
  puts "rake release          # Create tag v#{GitGameShow::VERSION} and build and push git_game_show-#{GitGameShow::VERSION}.gem to rubygems.org"
  puts "rake spec             # Run RSpec tests"
end