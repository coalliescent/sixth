#if !TESTING
import AppKit
import Network

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!      // permanent app icon, popover anchor
    private let popover = NSPopover()

    // Core
    private let api = PandoraAPI()
    private var audioPlayer: AudioPlayer!
    private var hotKeyManager: HotKeyManager!
    private var notificationManager: NotificationManager!
    private var scrollingTitle: ScrollingTitle!

    // View controllers
    private var playerVC: PlayerViewController!
    private var loginVC: LoginViewController!
    private var stationListVC: StationListViewController!
    private var settingsVC: SettingsViewController!

    // Popover dismissal monitors
    private var clickOutsideMonitor: Any?
    private var appDeactivationObserver: Any?

    // Network
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    // State
    private var stations: [Station] = []
    private var currentStation: Station?
    private var isLoggedIn = false
    private var isFetchingTracks = false
    private var currentTrackLiked = false
    private var currentFeedbackId: String?
    private var settingsFromLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Permanent app icon (popover anchors here)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Sixth")
            }
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: .leftMouseDown)
        }

        // Popover
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 130)
        popover.animates = false

        // Services
        audioPlayer = AudioPlayer(api: api)
        hotKeyManager = HotKeyManager()
        notificationManager = NotificationManager()
        scrollingTitle = ScrollingTitle()

        // Restore saved settings (default to true on first launch)
        if let saved = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool {
            notificationManager.isEnabled = saved
        }
        if let saved = UserDefaults.standard.object(forKey: "scrollingTitleEnabled") as? Bool {
            scrollingTitle.isEnabled = saved
        }

        scrollingTitle.onClick = { [weak self] in self?.togglePopover() }

        // Setup hotkeys
        hotKeyManager.onPlayPause = { [weak self] in
            self?.audioPlayer.togglePlayPause()
        }
        hotKeyManager.onNextTrack = { [weak self] in
            self?.audioPlayer.playNext()
        }
        hotKeyManager.register()

        // Request notification permission
        notificationManager.requestPermission()

        // Setup audio player callbacks
        setupAudioPlayerCallbacks()

        // Setup view controllers
        setupViewControllers()

        // Network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkChange(isAvailable: path.status == .satisfied)
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.sixth.networkMonitor"))

        // Check for saved credentials
        if let creds = CredentialStore.loadCredentials() {
            showPlayer()
            performLogin(username: creds.username, password: creds.password)
        } else {
            showLogin()
        }
    }

    // MARK: - Audio Player Callbacks

    private func setupAudioPlayerCallbacks() {
        audioPlayer.onTrackChanged = { [weak self] track in
            guard let self = self else { return }
            let song = track.songName ?? "Unknown"
            let artist = track.artistName ?? "Unknown"
            self.playerVC.setControlsEnabled(true)
            self.playerVC.updateTrack(song: song, artist: artist)
            self.playerVC.updateAlbumArt(url: track.albumArtUrl)
            self.currentTrackLiked = track.songRating == 1
            self.currentFeedbackId = nil
            self.playerVC.highlightThumbsUp(track.songRating == 1)
            self.scrollingTitle.update(song: song, artist: artist)
            self.notificationManager.showNowPlaying(
                song: song, artist: artist, album: track.albumName ?? ""
            )
            self.playerVC.reloadHistory()
        }

        audioPlayer.onPlaybackStateChanged = { [weak self] isPlaying in
            self?.playerVC.updatePlayState(isPlaying: isPlaying)
            if isPlaying {
                self?.scrollingTitle.resume()
            } else {
                self?.scrollingTitle.pause()
            }
        }

        audioPlayer.onProgress = { [weak self] current, duration in
            self?.playerVC.updateProgress(current: current, duration: duration)
        }

        audioPlayer.onError = { [weak self] message in
            print("[App] playback error: \(message)")
            self?.playerVC.showError(message)
        }

        audioPlayer.onNeedMoreTracks = { [weak self] in
            guard let self = self else { return }
            if !self.isNetworkAvailable {
                self.enterOfflineState()
            } else {
                self.fetchMoreTracks()
            }
        }

        audioPlayer.onQueueStale = { [weak self] in
            guard let self = self else { return }
            if !self.isNetworkAvailable {
                print("[App] queue stale but offline — entering offline state")
                self.enterOfflineState()
            } else {
                print("[App] queue stale — initiating recovery")
                self.handleStaleQueue()
            }
        }
    }

    // MARK: - View Controllers

    private func setupViewControllers() {
        // Player
        playerVC = PlayerViewController()
        playerVC.onReplay = { [weak self] in
            self?.audioPlayer.replay()
        }
        playerVC.onPlayPause = { [weak self] in
            self?.audioPlayer.togglePlayPause()
        }
        playerVC.onNext = { [weak self] in
            self?.audioPlayer.playNext()
        }
        playerVC.onThumbsUp = { [weak self] in
            self?.thumbsUp()
        }
        playerVC.onThumbsDown = { [weak self] in
            self?.thumbsDown()
        }
        playerVC.onStations = { [weak self] in
            self?.showStationList()
        }
        playerVC.onSettings = { [weak self] in
            self?.showSettings()
        }
        playerVC.onAbout = { [weak self] in
            self?.showAbout()
        }
        playerVC.onQuit = {
            NSApp.terminate(nil)
        }
        playerVC.onHistoryToggled = { [weak self] isOpen in
            self?.toggleHistory(isOpen: isOpen)
        }
        playerVC.onHistoryThumbsUp = { [weak self] trackToken in
            self?.historyThumbsUp(trackToken: trackToken)
        }
        playerVC.onHistoryThumbsDown = { [weak self] trackToken in
            self?.historyThumbsDown(trackToken: trackToken)
        }
        playerVC.setControlsEnabled(false)

        // Login
        loginVC = LoginViewController()
        loginVC.onLogin = { [weak self] username, password in
            self?.performLogin(username: username, password: password)
        }
        loginVC.onQuit = { NSApp.terminate(nil) }
        loginVC.onSettings = { [weak self] in self?.showSettings() }
        loginVC.onAbout = { [weak self] in self?.showAbout() }

        // Station list
        stationListVC = StationListViewController()
        stationListVC.onStationSelected = { [weak self] station in
            self?.selectStation(station)
        }
        stationListVC.onBack = { [weak self] in
            self?.showPlayer()
        }

        // Settings
        settingsVC = SettingsViewController()
        settingsVC.onSignOut = { [weak self] in
            self?.signOut()
        }
        settingsVC.onBack = { [weak self] in
            guard let self = self else { return }
            if self.settingsFromLogin {
                self.showLogin()
            } else {
                self.showPlayer()
            }
        }
        settingsVC.onNotificationsToggled = { [weak self] enabled in
            self?.notificationManager.isEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
        }
        settingsVC.onScrollingTitleToggled = { [weak self] enabled in
            guard let self = self else { return }
            self.scrollingTitle.isEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "scrollingTitleEnabled")
            if enabled {
                self.scrollingTitle.resume()
            } else {
                self.scrollingTitle.pause()
            }
        }
    }

    // MARK: - Navigation

    private func showLogin() {
        popover.contentViewController = loginVC
        popover.contentSize = loginVC.preferredContentSize
    }

    private func showPlayer() {
        _ = playerVC.view // ensure viewDidLoad has run
        let historyOpen = UserDefaults.standard.bool(forKey: "historyTrayOpen")
        playerVC.setHistoryOpen(historyOpen)
        popover.contentViewController = playerVC
        popover.contentSize = playerVC.preferredContentSize
    }

    private func showStationList() {
        Task {
            do {
                let stationList = try await api.getStationList()
                self.stations = stationList
                self.stationListVC.update(stations: stationList)
            } catch {
                print("Failed to fetch stations: \(error)")
                self.playerVC.showError("Failed to load stations")
            }
        }
        stationListVC.currentStationToken = currentStation?.stationToken
        popover.contentViewController = stationListVC
        popover.contentSize = stationListVC.preferredContentSize
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Sixth"
        alert.informativeText = "A lightweight Pandora client for macOS."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            iconImage.size = NSSize(width: 128, height: 128)
            alert.icon = iconImage
        }

        let link = NSTextView()
        link.isEditable = false
        link.isSelectable = true
        link.drawsBackground = false
        link.textContainerInset = .zero
        let url = "https://github.com/coalliescent/sixth"
        let attrStr = NSMutableAttributedString(string: url)
        attrStr.addAttributes([
            .link: URL(string: url)!,
            .font: NSFont.systemFont(ofSize: 13),
        ], range: NSRange(location: 0, length: url.count))
        link.textStorage?.setAttributedString(attrStr)
        link.alignment = .center
        link.frame = NSRect(x: 0, y: 0, width: 280, height: 20)
        alert.accessoryView = link

        alert.runModal()
    }

    private func showSettings() {
        settingsFromLogin = popover.contentViewController === loginVC
        settingsVC.notificationsEnabled = notificationManager.isEnabled
        settingsVC.scrollingTitleEnabled = scrollingTitle.isEnabled
        popover.contentViewController = settingsVC
        popover.contentSize = settingsVC.preferredContentSize
    }

    // MARK: - Auth

    private func performLogin(username: String, password: String) {
        Task {
            do {
                try await api.partnerLogin()
                try await api.userLogin(username: username, password: password)
                isLoggedIn = true

                _ = CredentialStore.saveCredentials(username: username, password: password)

                let stationList = try await api.getStationList()
                stations = stationList

                showPlayer()

                let lastToken = UserDefaults.standard.string(forKey: "lastStationToken")
                let initial = stationList.first(where: { $0.stationToken == lastToken }) ?? stationList.first
                if let station = initial {
                    selectStation(station)
                }
            } catch {
                isLoggedIn = false
                let message: String
                if let pandoraError = error as? PandoraError {
                    switch pandoraError {
                    case .userLoginFailed:
                        message = "Invalid email or password"
                    case .partnerLoginFailed:
                        message = "Unable to connect to Pandora"
                    case .notLoggedIn:
                        message = "Session expired, please sign in again"
                    case .apiError(_, let msg):
                        message = msg
                    default:
                        message = "Something went wrong, please try again"
                    }
                } else if (error as? URLError) != nil {
                    if !self.isNetworkAvailable {
                        self.enterOfflineState()
                        return
                    }
                    message = "Network error, check your connection"
                } else {
                    message = "Something went wrong, please try again"
                }
                if popover.contentViewController is LoginViewController {
                    loginVC.showError(message)
                } else {
                    showLogin()
                    loginVC.showError(message)
                }
            }
        }
    }

    // MARK: - Station

    private func selectStation(_ station: Station) {
        currentStation = station
        UserDefaults.standard.set(station.stationToken, forKey: "lastStationToken")
        // Track recently-played order (most recent first)
        var played = UserDefaults.standard.stringArray(forKey: "recentlyPlayedStations") ?? []
        played.removeAll { $0 == station.stationToken }
        played.insert(station.stationToken, at: 0)
        UserDefaults.standard.set(played, forKey: "recentlyPlayedStations")
        isFetchingTracks = false  // cancel any in-flight fetch for old station
        audioPlayer.setStation(station.stationToken)
        showPlayer()
        playerVC.setControlsEnabled(false)
        playerVC.updateTrack(song: "", artist: "")
        playerVC.showLoading()
        fetchMoreTracks()
    }

    private func enqueueAndPrefetch(_ tracks: [PlaylistItem]) {
        for track in tracks {
            if let artUrl = track.albumArtUrl {
                ImageCache.shared.prefetch(artUrl)
            }
        }
        audioPlayer.enqueue(tracks)
    }

    private func fetchMoreTracks() {
        guard let station = currentStation else { return }
        guard !isFetchingTracks else {
            print("[App] fetchMoreTracks: already fetching, skipping")
            return
        }
        isFetchingTracks = true
        print("[App] fetchMoreTracks for station: \(station.stationName)")
        Task {
            defer { self.isFetchingTracks = false }
            do {
                let tracks = try await self.fetchTracksWithRetry(stationToken: station.stationToken)
                // Don't enqueue if station changed while we were fetching
                guard self.currentStation?.stationToken == station.stationToken else {
                    print("[App] fetchMoreTracks: station changed during fetch, discarding")
                    return
                }
                self.enqueueAndPrefetch(tracks)
            } catch {
                print("[App] fetchMoreTracks failed: \(error)")
                if !self.isNetworkAvailable {
                    self.enterOfflineState()
                } else if self.audioPlayer.currentTrack == nil || !self.audioPlayer.isPlaying {
                    self.playerVC.showError("Failed to load tracks")
                }
            }
        }
    }

    private func fetchTracksWithRetry(stationToken: String, attempt: Int = 0) async throws -> [PlaylistItem] {
        do {
            return try await api.getPlaylist(stationToken: stationToken)
        } catch let error as PandoraError {
            if isAuthError(error) && attempt == 0 {
                print("[App] auth error on fetch, re-authenticating...")
                try await reAuthenticate()
                return try await fetchTracksWithRetry(stationToken: stationToken, attempt: attempt + 1)
            }
            throw error
        } catch let error as URLError where attempt < 3 {
            // Fail fast on non-recoverable errors
            switch error.code {
            case .badURL, .unsupportedURL, .cancelled:
                throw error
            default:
                break
            }
            // Exponential backoff: ~1s, ~3s, ~9s with jitter
            let base = pow(3.0, Double(attempt))
            let jitter = Double.random(in: 0..<1)
            let delay = UInt64((base + jitter) * 1_000_000_000)
            print("[App] network error on fetch (attempt \(attempt)), retrying in \(String(format: "%.1f", base + jitter))s...")
            try await Task.sleep(nanoseconds: delay)
            return try await fetchTracksWithRetry(stationToken: stationToken, attempt: attempt + 1)
        }
    }

    private func reAuthenticate() async throws {
        guard let creds = CredentialStore.loadCredentials() else {
            throw PandoraError.notLoggedIn
        }
        print("[App] re-authenticating as \(creds.username)")
        try await api.partnerLogin()
        try await api.userLogin(username: creds.username, password: creds.password)
        isLoggedIn = true
    }

    private func handleStaleQueue() {
        guard let station = currentStation else { return }
        print("[App] handleStaleQueue: clearing queue, re-fetching for \(station.stationName)")
        audioPlayer.clearQueue()
        audioPlayer.stop()
        playerVC.showLoading()

        Task {
            do {
                try await self.reAuthenticate()
                let tracks = try await self.api.getPlaylist(stationToken: station.stationToken)
                print("[App] stale recovery: got \(tracks.count) fresh tracks")
                self.enqueueAndPrefetch(tracks)
            } catch {
                print("[App] stale recovery failed: \(error)")
                if !self.isNetworkAvailable {
                    self.enterOfflineState()
                } else {
                    self.playerVC.showError("Session expired — please sign in again")
                }
            }
        }
    }

    private func isAuthError(_ error: PandoraError) -> Bool {
        switch error {
        case .notLoggedIn:
            return true
        case .apiError(let code, _):
            return code == PandoraError.invalidAuthTokenCode
        default:
            return false
        }
    }

    // MARK: - Network State

    private func handleNetworkChange(isAvailable: Bool) {
        if !isAvailable && self.isNetworkAvailable {
            // Went offline
            self.isNetworkAvailable = false
            print("[App] network lost")
            if !audioPlayer.isPlaying {
                enterOfflineState()
            }
            // If playing, let the cached song finish — offline state
            // will trigger when onNeedMoreTracks/onQueueStale fires
        } else if isAvailable && !self.isNetworkAvailable {
            // Came back online
            self.isNetworkAvailable = true
            print("[App] network restored, resuming")
            exitOfflineState()
        }
    }

    private func enterOfflineState() {
        audioPlayer.stop()
        audioPlayer.clearQueue()
        playerVC.setHistoryOpen(false)
        popover.contentSize = playerVC.preferredContentSize
        playerVC.clearTrackDisplay()
        playerVC.showOffline()
        playerVC.updatePlayState(isPlaying: false)
        scrollingTitle.setIdle()
        print("[App] entered offline state")
    }

    private func exitOfflineState() {
        playerVC.hideOffline()
        guard let station = currentStation, isLoggedIn else { return }
        playerVC.showLoading()
        Task {
            do {
                try await self.reAuthenticate()
                let tracks = try await self.api.getPlaylist(stationToken: station.stationToken)
                print("[App] network recovery: got \(tracks.count) tracks")
                self.enqueueAndPrefetch(tracks)
            } catch {
                print("[App] network recovery failed: \(error)")
                self.playerVC.showError("Failed to resume playback")
            }
        }
    }

    // MARK: - Feedback

    private func thumbsUp() {
        guard let track = audioPlayer.currentTrack, let token = track.trackToken else { return }
        if currentTrackLiked {
            // Remove the like
            playerVC.highlightThumbsUp(false)
            currentTrackLiked = false
            let feedbackId = currentFeedbackId
            currentFeedbackId = nil
            Task {
                do {
                    if let fid = feedbackId {
                        try await api.deleteFeedback(feedbackId: fid)
                    } else {
                        // No feedbackId (track was already liked before this session) —
                        // send a new positive feedback to get the feedbackId, then delete it
                        let fid = try await api.addFeedback(trackToken: token, isPositive: true)
                        if let fid = fid {
                            try await api.deleteFeedback(feedbackId: fid)
                        }
                    }
                    TrackHistory.shared.updateRating(trackToken: token, newRating: 0)
                    self.playerVC.reloadHistory()
                } catch {
                    print("Remove thumbs up failed: \(error)")
                    self.currentTrackLiked = true
                    self.playerVC.highlightThumbsUp(true)
                }
            }
        } else {
            // Add the like
            playerVC.highlightThumbsUp(true)
            currentTrackLiked = true
            Task {
                do {
                    let feedbackId = try await api.addFeedback(trackToken: token, isPositive: true)
                    self.currentFeedbackId = feedbackId
                    TrackHistory.shared.updateRating(trackToken: token, newRating: 1)
                    self.playerVC.reloadHistory()
                } catch {
                    print("Thumbs up failed: \(error)")
                    self.currentTrackLiked = false
                    self.playerVC.highlightThumbsUp(false)
                }
            }
        }
    }

    private func thumbsDown() {
        guard let track = audioPlayer.currentTrack, let token = track.trackToken else { return }
        Task {
            do {
                _ = try await api.addFeedback(trackToken: token, isPositive: false)
                self.audioPlayer.playNext()
            } catch {
                print("Thumbs down failed: \(error)")
            }
        }
    }

    // MARK: - History

    private func toggleHistory(isOpen: Bool) {
        UserDefaults.standard.set(isOpen, forKey: "historyTrayOpen")
        let newSize = NSSize(width: 360, height: isOpen ? 390 : 130)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.popover.contentSize = newSize
        }
    }

    private func historyThumbsUp(trackToken: String) {
        let entries = TrackHistory.shared.entries
        guard let entry = entries.first(where: { $0.trackToken == trackToken }) else { return }
        let wasLiked = entry.songRating == 1
        let newRating = wasLiked ? 0 : 1

        TrackHistory.shared.updateRating(trackToken: trackToken, newRating: newRating)
        playerVC.reloadHistory()

        // Sync with currently playing track if it matches
        if let current = audioPlayer.currentTrack, current.trackToken == trackToken {
            currentTrackLiked = newRating == 1
            playerVC.highlightThumbsUp(newRating == 1)
        }

        Task {
            do {
                if wasLiked {
                    // Unlike: add feedback to get ID, then delete
                    let fid = try await api.addFeedback(trackToken: trackToken, isPositive: true)
                    if let fid = fid {
                        try await api.deleteFeedback(feedbackId: fid)
                    }
                } else {
                    _ = try await api.addFeedback(trackToken: trackToken, isPositive: true)
                }
            } catch {
                print("History thumbs up failed: \(error)")
                // Revert
                TrackHistory.shared.updateRating(trackToken: trackToken, newRating: wasLiked ? 1 : 0)
                self.playerVC.reloadHistory()
                if let current = self.audioPlayer.currentTrack, current.trackToken == trackToken {
                    self.currentTrackLiked = wasLiked
                    self.playerVC.highlightThumbsUp(wasLiked)
                }
            }
        }
    }

    private func historyThumbsDown(trackToken: String) {
        Task {
            do {
                _ = try await api.addFeedback(trackToken: trackToken, isPositive: false)
            } catch {
                print("History thumbs down failed: \(error)")
            }
        }
    }

    // MARK: - Sign Out

    private func signOut() {
        audioPlayer.stop()
        Task { await api.logout() }
        CredentialStore.deleteCredentials()
        isLoggedIn = false
        stations = []
        currentStation = nil
        UserDefaults.standard.set(false, forKey: "historyTrayOpen")
        playerVC.setHistoryOpen(false)
        scrollingTitle.setIdle()
        showLogin()
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)

            // Refresh play state after show so it runs after lazy viewDidLoad/setupUI
            if popover.contentViewController === playerVC {
                playerVC.updatePlayState(isPlaying: audioPlayer.isPlaying)
            }

            // Monitor clicks outside the app to dismiss
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }

            // Monitor app deactivation (Cmd-Tab, click desktop, etc.)
            appDeactivationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closePopover()
                }
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let observer = appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivationObserver = nil
        }

        if popover.contentViewController !== playerVC &&
           popover.contentViewController !== loginVC {
            if settingsFromLogin {
                showLogin()
            } else {
                showPlayer()
            }
        }
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return false
    }
}
#endif
