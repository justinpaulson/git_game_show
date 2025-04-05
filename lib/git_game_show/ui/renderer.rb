module GitGameShow
  # Main UI renderer for terminal display
  class Renderer
    def initialize
      @message_log = []
      @cursor = TTY::Cursor

      # Get terminal dimensions
      @terminal_width = `tput cols`.to_i rescue 80
      @terminal_height = `tput lines`.to_i rescue 24

      # Calculate layout
      @main_width = (@terminal_width * 0.7).to_i
      @sidebar_width = @terminal_width - @main_width - 3 # 3 for border

      # The fixed line for command input (near bottom of screen)
      @command_line = @terminal_height - 3
    end

    def setup
      # Clear screen and hide cursor
      print @cursor.clear_screen
      print @cursor.hide

      # Draw initial UI
      draw_ui_frame
    end

    def cleanup
      print @cursor.show  # Make sure cursor is visible
      print @cursor.clear_screen
    end
    
    def draw_ui_frame
      # Clear screen
      print @cursor.clear_screen

      # Draw horizontal divider line between main area and command area
      print @cursor.move_to(0, @command_line - 1)
      print "═" * (@terminal_width - @sidebar_width - 3) + "╧" + "═" * (@sidebar_width + 2)

      # Draw vertical divider line between main area and sidebar
      print @cursor.move_to(@main_width, 0)
      print "│"
      print @cursor.move_to(@main_width, 1)
      print "│"
      print @cursor.move_to(@main_width, 2)
      print "╞═"
      (3...@command_line-1).each do |line|
        print @cursor.move_to(@main_width, line)
        print "│"
      end
    end

    def draw_welcome_banner
      # Position cursor at top left
      lines = [
        " ██████╗ ".colorize(:red) + "  ██████╗ ".colorize(:green) + "  █████╗".colorize(:blue),
        "██╔════╝ ".colorize(:red) + " ██╔════╝ ".colorize(:green) + " ██╔═══╝".colorize(:blue),
        "██║  ███╗".colorize(:red) + " ██║  ███╗".colorize(:green) + " ███████╗".colorize(:blue),
        "██║   ██║".colorize(:red) + " ██║   ██║".colorize(:green) + " ╚════██║".colorize(:blue),
        "╚██████╔╝".colorize(:red) + " ╚██████╔╝".colorize(:green) + " ██████╔╝".colorize(:blue),
        " ╚═════╝ ".colorize(:red) + "  ╚═════╝ ".colorize(:green) + " ╚═════╝ ".colorize(:blue),
      ]

      start_y = 1
      lines.each_with_index do |line, i|
        print @cursor.move_to((@main_width - 28) / 2, start_y + i)
        print line
      end
    end

    def draw_join_link(join_link)
      # Copy the join link to clipboard
      Clipboard.copy(join_link)

      link_box_width = [join_link.length + 6, @main_width - 10].min
      start_x = (@main_width - link_box_width) / 2
      start_y = 8

      print @cursor.move_to(start_x, start_y)
      print "╭" + "─" * (link_box_width - 2) + "╮"

      print @cursor.move_to(start_x, start_y + 1)
      print "│" + " Join Link (Copied to Clipboard) ".center(link_box_width - 2).colorize(:green) + "│"

      print @cursor.move_to(start_x, start_y + 2)
      print "│" + join_link.center(link_box_width - 2).colorize(:yellow) + "│"

      print @cursor.move_to(start_x, start_y + 3)
      print "╰" + "─" * (link_box_width - 2) + "╯"

      # Also log that the link was copied
      log_message("Join link copied to clipboard", :green)
    end

    def log_message(message, color = :white)
      # Add message to log
      @message_log << {text: message, color: color}

      # Keep only last few messages
      @message_log = @message_log.last(15) if @message_log.size > 15

      # Redraw message area
      draw_message_area

      # Return cursor to command prompt
      draw_command_prompt
    end

    def draw_message_area
      # Calculate message area dimensions
      message_area_start = 18
      message_area_height = @command_line - message_area_start - 2

      # Clear message area
      (message_area_start..(@command_line-2)).each do |line|
        print @cursor.move_to(1, line)
        print " " * (@main_width - 2)
      end

      # Draw most recent messages
      display_messages = @message_log.last(message_area_height)
      display_messages.each_with_index do |msg, index|
        print @cursor.move_to(1, message_area_start + index)
        # Truncate message to fit within main width to prevent overflow
        truncated_text = msg[:text][0...(@main_width - 3)]
        print truncated_text.colorize(msg[:color])
      end
    end

    def draw_command_prompt
      # Clear command line and two lines below to prevent commit info bleeding
      print @cursor.move_to(0, @command_line)
      print " " * @terminal_width
      print @cursor.move_to(0, @command_line + 1)
      print " " * @terminal_width
      print @cursor.move_to(0, @command_line + 2)
      print " " * @terminal_width

      # Draw command prompt
      print @cursor.move_to(0, @command_line)
      print "Command> ".colorize(:green)

      # Position cursor after prompt
      print @cursor.move_to(9, @command_line)
      print @cursor.show
    end

    def draw_game_over(winner, scores)
      # Safety check for winner
      if !winner || !winner[0] || !winner[1]
        log_message("Error: Invalid winner data", :red)
        return
      end

      # Create a safe copy of scores to work with
      safe_scores = {}
      begin
        if scores && !scores.empty?
          scores.each do |player, score|
            next unless player && player.to_s != ""
            safe_scores[player.to_s] = score.to_i
          end
        end
      rescue => e
        log_message("Error copying scores: #{e.message}", :red)
      end
      
      # Use log messages for display
      divider = "=" * (@main_width - 5)
      log_message(divider, :yellow)
      log_message("🏆 GAME OVER - FINAL SCORES 🏆", :yellow)
      
      # Announce winner
      winner_name = winner[0].to_s
      winner_name = winner_name.length > 20 ? "#{winner_name[0...17]}..." : winner_name
      winner_score = winner[1].to_i
      log_message("Winner: #{winner_name} with #{winner_score} points!", :green)
      
      # Show leaderboard
      log_message("Leaderboard:", :cyan)
      
      # Sort scores safely
      sorted_scores = []
      begin
        sorted_scores = safe_scores.sort_by { |_, score| -(score || 0) }.to_a
      rescue => e
        log_message("Error sorting scores for display: #{e.message}", :red)
        sorted_scores = safe_scores.to_a
      end
      
      max_to_show = 10
      entries_to_show = [sorted_scores.size, max_to_show].min
      
      sorted_scores.take(entries_to_show).each_with_index do |score_entry, index|
        # Extra safety check for each entry
        next unless score_entry && score_entry.is_a?(Array) && score_entry.size >= 2
        
        name = score_entry[0]
        score = score_entry[1]
        
        # Safely handle name and score
        player_name = name.to_s
        player_score = score.to_i
        
        # Truncate name if needed
        display_name = player_name.length > 15 ? "#{player_name[0...12]}..." : player_name
        
        # Format based on position
        case index
        when 0
          log_message("🥇 #{display_name}: #{player_score} points", :yellow)
        when 1
          log_message("🥈 #{display_name}: #{player_score} points", :light_blue)
        when 2
          log_message("🥉 #{display_name}: #{player_score} points", :light_magenta)
        else
          log_message("#{(index + 1).to_s}. #{display_name}: #{player_score} points", :white)
        end
      end
      
      # If there are more players than shown, add a note
      if sorted_scores.size > max_to_show
        log_message("... and #{sorted_scores.size - max_to_show} more", :light_black)
      end
      
      log_message(divider, :yellow)
      log_message("Ready for a new game! Type 'start' when players have joined.", :green)
    end
  end
end