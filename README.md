# Sixth

A macOS menubar Pandora client. Pure Swift/AppKit, no Xcode required.

## Features

- **Menubar app** — lives in your status bar, stays out of the way
- **Scrolling now-playing** — current track scrolls in the menubar
- **Station switching** — browse and select from your Pandora stations
- **Playback controls** — play/pause, skip, thumbs up/down
- **Global hotkeys** — media key support via Carbon
- **macOS notifications** — track change alerts
- **Keychain storage** — credentials stored securely in macOS Keychain
- **No dependencies** — no SPM packages, no CocoaPods, no Xcode project

## Requirements

- macOS (built and tested on macOS 14 Sonoma)
- Xcode Command Line Tools (`xcode-select --install`)
- A Pandora account

## Build & Run

```bash
./build.sh        # produces Sixth.app and SixthTests
open Sixth.app    # launch
```

The build script compiles with `swiftc`, creates an `.app` bundle, and optionally code-signs it. No Xcode project needed.

### Tests

```bash
./SixthTests      # run unit tests
```

Tests use a custom runner (not XCTest) and compile with `-DTESTING` to exclude UI code.

## Architecture

Built with `swiftc -parse-as-library` using AppKit, AVFoundation, Carbon, Security, and Network frameworks.

| File | Role |
|------|------|
| `Main.swift` | Entry point |
| `AppDelegate.swift` | Status item, popover, navigation, app lifecycle |
| `PlayerViewController.swift` | Album art, controls, progress bar |
| `LoginViewController.swift` | Login form |
| `StationListViewController.swift` | Station picker |
| `SettingsViewController.swift` | Settings screen |
| `AudioPlayer.swift` | AVPlayer wrapper, track queue management |
| `PandoraAPI.swift` | Pandora JSON API client |
| `Models.swift` | Data models (Station, Track, API responses) |
| `BlowfishCrypto.swift` | Blowfish encrypt/decrypt for Pandora API |
| `CredentialStore.swift` | Keychain credential storage |
| `HotKeyManager.swift` | Global media key handling |
| `NotificationManager.swift` | macOS notification support |
| `ScrollingTitle.swift` | Scrolling now-playing text in menubar |

## License

[MIT](LICENSE)
