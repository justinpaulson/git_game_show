# Git Game Show

A multiplayer trivia game based on Git repository commit history.

## Overview

Git Game Show transforms your project's Git commit history into a live, multiplayer trivia game. One user hosts a session, other players join remotely, and the system rotates through rounds of different question-based "mini-games," awarding points and declaring a final winner.

## Features

- **Host a Game**: Create a game server for others to join
- **Join Games**: Connect to games hosted by others
- **Multiple Mini-Games**: Different question types based on Git history
- **Real-time Multiplayer**: Compete with others over WebSockets
- **Scoring System**: Track points and determine a winner

## Installation

### Option 1: Install as a Ruby Gem (Recommended)

```bash
gem install git_game_show
```

This will install the `git-game-show` command globally on your system.

If you encounter permission issues or the command is not found:

```bash
# Fix permissions if needed
chmod +x $(gem which git_game_show | sed 's/lib\/git_game_show.rb/bin\/git-game-show/')

# For rbenv users
rbenv rehash

# For asdf users
asdf reshim ruby
```

### Option 2: Manual Installation

```bash
# Clone the repository
git clone https://github.com/justinpaulson/git_game_show.git
cd git_game_show

# Install dependencies
bundle install

# Build and install the gem locally
rake install
```

## Usage

### Hosting a Game

To host a game session:

If installed as a gem:
```bash
git-game-show host --repo-path /path/to/git/repo
```

If installed from source:
```bash
git-game-show host --repo-path /path/to/git/repo
```

Options:
- `--repo-path`: Optional. Path to the Git repository to use (defaults to current directory).
- `--port`: Optional. Port to run the server on (defaults to 3030).
- `--rounds`: Optional. Number of rounds to play (defaults to 3).
- `--password`: Optional. Password for players to join (auto-generated if not provided).

A secure join link will be generated automatically with a memorable random password. Just share this link with your players.

### Joining a Game

To join an existing game session:

If installed as a gem:
```bash
git-game-show join "gitgame://host_ip:port/password" --name yourname
```

If installed from source:
```bash
git-game-show join "gitgame://host_ip:port/password" --name yourname
```

Parameters:
- `join link`: The secure link provided by the host (includes host address and password)
- `--name`: Optional. Your display name in the game. If not provided, you'll be prompted.

You can also simply run `git-game-show` and select "Join a game" from the interactive menu.

## Mini-Games

The game includes several mini-games based on Git repository data:

1. **Author Quiz**: Guess which team member made each commit
2. **Commit Message Quiz**: Match the commit message to the right changed file
3. **Commit Timeline**: Put commits in chronological order
4. **Complete the Commit**: Complete the missing part of commit messages

## Requirements

- Ruby 2.7 or higher
- A Git repository with commit history
- Network access between host and players

## License

MIT

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
