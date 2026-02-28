# Sixth

macOS menubar Pandora client. Pure Swift/AppKit, no Xcode required.

## Build & Run

```bash
./build.sh        # produces Sixth.app and SixthTests
open Sixth.app    # launch
./SixthTests      # run tests
```

## Build Details

- `swiftc` with `-parse-as-library`, no SPM
- Frameworks: AppKit, AVFoundation, Carbon (hotkeys), Security (keychain)
- Tests compile with `-DTESTING` flag, which excludes all UI code (`#if !TESTING`)
- Code signing with "Sixth Dev" identity (optional, required for keychain tests)
- No external dependencies

## Source Layout

`Sources/` (15 files):
- `Main.swift` — entry point
- `AppDelegate.swift` — status item, popover, navigation, app lifecycle
- `PlayerViewController.swift` — main player UI (album art, controls, progress, history tray)
- `LoginViewController.swift` — login form
- `StationListViewController.swift` — station picker (table view)
- `SettingsViewController.swift` — settings screen
- `AudioPlayer.swift` — AVPlayer wrapper, track queue management
- `TrackHistory.swift` — recently played track history (persisted via UserDefaults, capped at 100)
- `PandoraAPI.swift` — Pandora JSON API client (partner/user login, playlist, feedback)
- `Models.swift` — data models (Station, Track, API responses)
- `BlowfishCrypto.swift` — Blowfish encrypt/decrypt for Pandora API
- `CredentialStore.swift` — keychain storage for credentials
- `HotKeyManager.swift` — global media key handling via Carbon
- `NotificationManager.swift` — macOS notification support
- `ScrollingTitle.swift` — scrolling now-playing text in menubar

`Tests/` (6 files):
- `TestMain.swift` — custom test runner (not XCTest)
- `BlowfishCryptoTests.swift`, `ModelsTests.swift`, `PandoraAPITests.swift`, `TrackHistoryTests.swift`, `IntegrationTests.swift`
