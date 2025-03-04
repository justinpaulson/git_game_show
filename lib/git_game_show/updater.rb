require 'net/http'
require 'json'
require 'uri'
require 'rubygems'
require 'colorize'
require 'tty-prompt'

module GitGameShow
  class Updater
    class << self
      def check_for_updates
        current_version = GitGameShow::VERSION
        latest_version = fetch_latest_version

        return if latest_version.nil?
        
        # Compare versions
        if newer_version_available?(current_version, latest_version)
          display_update_prompt(current_version, latest_version)
        end
      end

      private

      def fetch_latest_version
        begin
          uri = URI.parse("https://rubygems.org/api/v1/gems/git_game_show.json")
          response = Net::HTTP.get_response(uri)
          
          if response.code == "200"
            data = JSON.parse(response.body)
            return data["version"]
          else
            # Silently fail on network errors
            return nil
          end
        rescue => e
          # Silently fail on connection errors
          return nil
        end
      end

      def newer_version_available?(current, latest)
        # Convert version strings to comparable arrays
        current_parts = current.split('.').map(&:to_i)
        latest_parts = latest.split('.').map(&:to_i)

        # Compare each part numerically
        latest_parts.zip(current_parts).each do |latest_part, current_part|
          return true if latest_part > current_part
          return false if latest_part < current_part
        end

        # If we get here and versions are different lengths, the longer one is newer
        return latest_parts.length > current_parts.length
      end

      def display_update_prompt(current_version, latest_version)
        prompt = TTY::Prompt.new
        
        # Clear the terminal for better visibility
        puts "\n\n"
        
        puts "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓".colorize(:cyan)
        puts "┃           UPDATE AVAILABLE FOR GIT GAME SHOW                   ┃".colorize(:cyan)
        puts "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫".colorize(:cyan)
        puts "┃                                                                ┃".colorize(:cyan)
        puts "┃  Current version: #{current_version.ljust(38)}  ┃".colorize(:cyan)
        puts "┃  Latest version:  #{latest_version.ljust(38)}  ┃".colorize(:cyan)
        puts "┃                                                                ┃".colorize(:cyan)
        puts "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛".colorize(:cyan)
        puts "\n"
        
        update_now = prompt.yes?("Would you like to update now?")
        
        if update_now
          perform_update
        else
          puts "You can update later by running: gem update git_game_show".colorize(:yellow)
          puts "\nContinuing with current version...\n\n"
        end
      end

      def perform_update
        puts "\nUpdating Git Game Show to the latest version...".colorize(:cyan)
        
        begin
          # Use system to capture both stdout and stderr
          update_command = "gem update git_game_show"
          result = system(update_command)
          
          if result
            puts "\n✅ Update completed successfully!".colorize(:green)
            puts "Please restart Git Game Show to use the new version.".colorize(:yellow)
            exit(0)
          else
            puts "\n❌ Update failed with exit code: #{$?.exitstatus}".colorize(:red)
            puts "You can manually update by running: gem update git_game_show".colorize(:yellow)
          end
        rescue => e
          puts "\n❌ Update failed: #{e.message}".colorize(:red)
          puts "You can manually update by running: gem update git_game_show".colorize(:yellow)
        end
      end
    end
  end
end