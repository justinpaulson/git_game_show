module GitGameShow
  # Manages the sidebar display
  class Sidebar
    def initialize(renderer)
      @renderer = renderer
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

    def draw_header
      # Draw sidebar header
      print @cursor.move_to(@main_width + 2, 1)
      print "Players".colorize(:cyan)

      print @cursor.move_to(@main_width + 2, 2)
      print "═" * (@sidebar_width - 2)
    end

    def update_player_list(players, scores)
      draw_header

      # Clear player area
      (3..(@command_line-3)).each do |line|
        print @cursor.move_to(@main_width + 2, line)
        print " " * (@sidebar_width - 2)
      end

      # Show player count
      print @cursor.move_to(@main_width + 2, 3)
      print "Total: #{players.size} player(s)".colorize(:yellow)

      # Calculate available space for the player list
      max_visible_players = @command_line - 8 # Allow space for headers, counts and scrolling indicators

      # List players with scrolling if needed
      if players.empty?
        print @cursor.move_to(@main_width + 2, 5)
        print "Waiting for players...".colorize(:light_black)
      else
        # Sort players by score (highest first)
        sorted_players = players.sort_by { |name| -(scores[name] || 0) }

        # Show scrolling indicator if needed
        if players.size > max_visible_players
          print @cursor.move_to(@main_width + 2, 4)
          print "Showing #{max_visible_players} of #{players.size}:".colorize(:yellow)
        end

        # Determine which players to display (show top N players by score)
        visible_players = sorted_players.take(max_visible_players)

        # Display visible players with their scores
        visible_players.each_with_index do |name, index|
          print @cursor.move_to(@main_width + 2, 5 + index)

          # Get score (default to 0 if not found)
          score = scores[name] || 0
          score_str = score.to_s

          # Calculate available space for name and right-justified score
          usable_width = @sidebar_width - 6
          prefix_width = 3 # Account for emoji or number + dot + space

          # Apply medal emoji for top 3 players when in game
          prefix = ""
          if scores.any?
            prefix = case index
                     when 0 then "🥇 "
                     when 1 then "🥈 "
                     when 2 then "🥉 "
                     else "#{index + 1}. "
                     end
          else
            prefix = "#{index + 1}. "
          end

          # Calculate how much space we have for the name
          max_name_length = usable_width - score_str.length - 1 # 1 space before score

          # Truncate long names
          truncated_name = name.length > max_name_length ?
                           "#{name[0...(max_name_length-3)]}..." :
                           name

          # Print player name
          print @cursor.move_to(@main_width + 2, 5 + index)
          print "#{prefix}#{truncated_name}".colorize(:light_blue)

          # Print right-justified score
          score_position = @main_width + usable_width
          print @cursor.move_to(score_position, 5 + index)
          print score_str.colorize(:light_blue)
        end

        # If there are more players than can be shown, add an indicator
        if players.size > max_visible_players
          print @cursor.move_to(@main_width + 2, 5 + max_visible_players)
          print "... and #{players.size - max_visible_players} more".colorize(:light_black)
        end
      end

      # Return cursor to command prompt
      @renderer.draw_command_prompt
    end
  end
end
