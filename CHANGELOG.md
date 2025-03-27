# Changelog
## [0.2.2] - 2025-03-27
- Refactored main game server, fixed some small bugs.

## [0.2.1] - 2025-03-12
- Increased timeout between games, cleaned up some ui issues

## [0.2.0] - 2025-03-12

### Changed
- Bumped to 0.2.0 for first stable minor release with all initial games implemented

## [0.1.11] - 2025-03-11

### Added
- New mini-game: Blame Game - identify who committed a specific line of code

## [0.1.10] - 2025-03-10

### Added
- New mini-game: Branch Detective

### Changed
- Fixed scoreboard display in player client

## [0.1.9] - 2025-03-07

### Fixed
- File quiz was defaulting to sample questions, works now.

## [0.1.8] - 2025-03-07

### Fixed
- Fixed file quiz
- Updated updater UI
- Fixed ngrok server integration
- Updated UI and scoring on date ordering

## [0.1.2] - 2025-03-04

### Fixed
- Added post-installation hook that automatically sets executable permissions
- Added automatic environment rehashing for rbenv and asdf users
- Improved installation experience with helpful messages

## [0.1.1] - 2025-03-04

### Fixed
- Improved executable permissions management for better installation experience
- Added troubleshooting instructions for Ruby environment managers (rbenv/asdf)
- Enhanced installation documentation

## [0.1.0] - 2025-03-02

### Added
- Initial release of Git Game Show as a Ruby gem
- Four mini-games: Author Quiz, Commit Message Quiz, Commit Message Completion, Date Ordering Quiz
- Multiplayer functionality via WebSockets
- Host and client components
- Command line interface for easy use
- Interactive UI with colorized output
