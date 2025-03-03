# Publishing Git Game Show as a Ruby Gem

This document provides step-by-step instructions for building, testing, and publishing the Git Game Show Ruby gem.

## Prerequisites

1. Make sure you have a RubyGems.org account
2. Configure your local environment for RubyGems:
   ```bash
   gem signin
   ```

## Building and Testing Locally

1. Build the gem:
   ```bash
   bundle exec rake build
   ```
   This will create a gem file in the `pkg` directory.

2. Install the gem locally to test it:
   ```bash
   bundle exec rake local_install
   ```

3. Test the locally installed gem:
   ```bash
   git-game-show version
   git-game-show
   ```

## Releasing to RubyGems.org

When you're ready to release a new version:

1. Update the version number in `lib/git_game_show/version.rb`

2. Update the CHANGELOG.md file with details about the new version

3. Commit your changes:
   ```bash
   git add lib/git_game_show/version.rb CHANGELOG.md
   git commit -m "Bump version to X.Y.Z"
   ```

4. Release the gem:
   ```bash
   bundle exec rake release
   ```
   This will:
   - Create a Git tag for the version
   - Push git commits and tags
   - Build the gem
   - Push the gem to RubyGems.org

## After Release

1. Verify the gem is available on RubyGems.org:
   ```bash
   gem search git_game_show
   ```

2. Try installing from RubyGems.org:
   ```bash
   gem install git_game_show
   ```

## Maintenance

- For bug fixes: increment the patch version (0.1.X)
- For new features: increment the minor version (0.X.0)
- For breaking changes: increment the major version (X.0.0)

Always test thoroughly before releasing to ensure a quality experience for users.