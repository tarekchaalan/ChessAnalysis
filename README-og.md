# ChessAnalysis

An iOS app for downloading Chess.com games, analyzing them on-device with Stockfish, and reviewing move quality with a Chess.com-inspired UI.

## Features

- Download games from Chess.com by username
- Search games by player name
- Filter by time control, game end, and date range
- Offline storage of selected games
- On-device analysis with Stockfish (no cloud required)
- Live analysis progress with percentages
- Game summary with evaluation graph, accuracies, move classifications, and phase ratings
- Interactive review with eval bar, move highlights, move list, board flip, and mate line view
- Paste PGNs directly from the Games page
- Move sounds during review
- Board theme picker with multiple color palettes
- Low power analysis mode with automatic enable under 10% battery

## Requirements

- Xcode 15+
- iOS 17+
- macOS Sonoma or newer for development

## Setup

1. Open `ChessAnalysis.xcodeproj` in Xcode.
2. Select a simulator or device.
3. Build and run.

## Usage

1. Go to **Settings** and enter your Chess.com username.
2. Open **Games** and refresh to fetch your games.
3. Tap the download icon to store a game locally. The app will analyze it in the background. Progress appears in both tabs.
4. Go to **Analyzed Games** to review completed analyses (or in-progress ones).
5. Swipe to delete a single analysis from **Analyzed Games**.
6. Use the **+** button to paste PGNs manually.
7. Customize the board theme in **Settings → Board Theme**.

## Analysis Notes

- Analysis runs on-device using Stockfish. Performance depends on the device.
- Low Power Analysis reduces resource use at the cost of accuracy.
- Analysis continues in the background while the app is still running.
- Accuracy and move classifications are based on an Expected Points model inspired by Chess.com.
- Games with no moves are handled gracefully (no analysis performed).

## Data & Storage

- Downloaded PGNs are stored locally in the app’s documents directory.
- Analyses are stored in Core Data.
- A storage cap is enforced; oldest analyzed games are overwritten first.

## Project Structure

- `ChessAnalysis/` – SwiftUI app source
- `ChessAnalysis/Engine/` – Stockfish wrapper
- `ChessAnalysis/Assets.xcassets/` – icons, pieces, classifications, themes

## Privacy

- No server-side analysis; all computation is local.
- Chess.com data is fetched from public endpoints.

## Reporting

- If a PGN is invalid, you can report it from the Games screen.
- Reports attach the PGN and error details to an email draft.

## Development

- SwiftUI for UI
- Async/await for networking and background analysis
- Core Data for analysis persistence

## License

[MIT License](LICENSE)