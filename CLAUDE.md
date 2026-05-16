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

`Sources/` (16 files):
- `Main.swift` — entry point
- `AppDelegate.swift` — status item, popover, navigation, app lifecycle
- `PlayerViewController.swift` — main player UI (album art, controls, progress, history/lyrics tray, seek overlay)
- `LoginViewController.swift` — login form
- `StationListViewController.swift` — station picker (table view)
- `SettingsViewController.swift` — settings screen
- `AudioPlayer.swift` — AVPlayer wrapper, track queue management, seek, 4h in-memory cache of recently-played `PlaylistItem`s for history replay
- `LyricsProvider.swift` — lyrics fetching (LRCLIB + Lyrics.ovh fallback), LRC parser, in-memory cache
- `TrackHistory.swift` — recently played track history (persisted via UserDefaults, capped at 100)
- `PandoraAPI.swift` — Pandora JSON API client (partner/user login, playlist, feedback)
- `Models.swift` — data models (Station, Track, API responses)
- `BlowfishCrypto.swift` — Blowfish encrypt/decrypt for Pandora API
- `CredentialStore.swift` — keychain storage for credentials
- `HotKeyManager.swift` — global media key handling via Carbon
- `NotificationManager.swift` — macOS notification support
- `ScrollingTitle.swift` — scrolling now-playing text in menubar

`Tests/` (7 files):
- `TestMain.swift` — custom test runner (not XCTest)
- `BlowfishCryptoTests.swift`, `ModelsTests.swift`, `PandoraAPITests.swift`, `TrackHistoryTests.swift`, `LyricsProviderTests.swift`, `IntegrationTests.swift`

## Lyrics & Tray

The player has a shared tray below the main UI with two mutually exclusive modes toggled by bottom-row buttons:
- **History** (`list.bullet` icon) — recently played tracks with thumbs up/down. Rows whose `PlaylistItem` is still in the AudioPlayer cache (4h TTL) also get a replay button left of thumbs-down; tapping it pushes the current track into history and plays the chosen one without disturbing the upstream queue.
- **Lyrics** (🗣️ icon) — song lyrics fetched from LRCLIB (synced + plain) with Lyrics.ovh fallback

The tray is resizable via a grabber bar at the bottom edge (drag to resize, snap-close below 60px, min 200px when open, max 500px). Height and mode are persisted in UserDefaults (`trayOpen`, `trayMode`, `trayHeight`).

Synced lyrics highlight the current line (white/semibold) and auto-scroll during playback. Plain lyrics display in white with paragraph spacing.

## Interactive Playhead

The progress bar has a transparent seek overlay with a silver playhead circle (visible on hover). Click or drag anywhere on the bar to seek within the track. Progress bar animation is suppressed via CATransaction.
