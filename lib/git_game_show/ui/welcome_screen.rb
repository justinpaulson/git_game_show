module GitGameShow
  # Handles the welcome screen display
  class WelcomeScreen
    def self.display_ggs
      # Clear screen
      system('clear') || system('cls')

      puts ""
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

    def self.display_game_logo
      # Clear screen
      system('clear') || system('cls')

      puts ""
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
  end
end
