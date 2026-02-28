import Foundation

enum IntegrationTests {
    static func runAll() {
        guard let creds = CredentialStore.loadTestCredentials() else {
            print("  ⚠ Skipping integration tests — no credentials (run: ./sixth-creds store <user> <pass>)")
            return
        }

        let api = PandoraAPI()
        let sem = DispatchSemaphore(value: 0)
        var stations: [Station] = []
        var loginOk = false

        // 1. Partner + user login
        Task {
            do {
                try await api.partnerLogin()
                try await api.userLogin(username: creds.username, password: creds.password)
                loginOk = true
            } catch {
                print("  ✗ integration login: \(error)")
            }
            sem.signal()
        }
        sem.wait()
        TestRunner.assert(loginOk, "integration: login succeeds")
        guard loginOk else { return }

        // 2. Get station list
        Task {
            do {
                stations = try await api.getStationList()
            } catch {
                print("  ✗ integration station list: \(error)")
            }
            sem.signal()
        }
        sem.wait()
        TestRunner.assert(!stations.isEmpty, "integration: station list non-empty")
        guard !stations.isEmpty else { return }

        let station = stations[0]
        print("  → Using station: \(station.stationName) (\(station.stationToken))")

        // 2b. Inspect raw station list JSON for art URL fields
        testRawStationList(api: api, sem: sem)

        // 3. Validate station metadata
        testStationMetadata(stations: stations)

        // 4. Get raw playlist response to inspect structure
        testRawPlaylistResponse(api: api, stationToken: station.stationToken, sem: sem)

        // 5. Try decoding through the API's getPlaylist method
        let tracks = testGetPlaylist(api: api, stationToken: station.stationToken, sem: sem)

        // 6. Add feedback (thumbs up) on first track
        if let track = tracks.first {
            testAddFeedback(api: api, trackToken: track.trackToken, sem: sem)
        }

        // 7. Verify all tracks have required fields
        testTrackFieldCompleteness(tracks: tracks)

        // 8. Invalid station token returns error
        testInvalidStationToken(api: api, sem: sem)

        // 9. Logout clears state, re-login works
        testLogoutAndRelogin(api: api, creds: creds, sem: sem)
    }

    private static func testStationMetadata(stations: [Station]) {
        for station in stations {
            TestRunner.assert(!station.stationId.isEmpty, "integration: station '\(station.stationName)' has id")
            TestRunner.assert(!station.stationToken.isEmpty, "integration: station '\(station.stationName)' has token")
            TestRunner.assert(!station.stationName.isEmpty, "integration: station has non-empty name")
        }
        // At least one station should NOT be QuickMix
        let hasRegular = stations.contains { $0.isQuickMix != true }
        TestRunner.assert(hasRegular, "integration: at least one non-QuickMix station")
    }

    private static func testRawStationList(api: PandoraAPI, sem: DispatchSemaphore) {
        var stations: [Station] = []
        Task {
            do {
                stations = try await api.getStationList()
            } catch {
                print("  ✗ station list for art test: \(error)")
            }
            sem.signal()
        }
        sem.wait()

        let withArt = stations.filter { $0.artUrl != nil }
        print("  → \(withArt.count)/\(stations.count) stations have artUrl")
        if let sample = withArt.first {
            print("  → Sample artUrl: \(sample.artUrl!.prefix(80))...")
        }
        // Most stations should have art (API returns it with includeStationArtUrl)
        TestRunner.assert(withArt.count > stations.count / 2, "integration: majority of stations have artUrl")
    }

    private static func testRawPlaylistResponse(api: PandoraAPI, stationToken: String, sem: DispatchSemaphore) {
        var rawJSON: String?
        var topLevelKeys: [String] = []
        var resultKeys: [String] = []

        Task {
            do {
                // Replicate what PandoraAPI.getPlaylist does, but capture raw data
                let data = try await api.getRawPlaylist(stationToken: stationToken)
                rawJSON = String(data: data, encoding: .utf8)

                // Parse as dictionary to inspect keys
                if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    topLevelKeys = Array(dict.keys).sorted()
                    if let result = dict["result"] as? [String: Any] {
                        resultKeys = Array(result.keys).sorted()
                    }
                }
            } catch {
                print("  ✗ raw playlist fetch: \(error)")
            }
            sem.signal()
        }
        sem.wait()

        if let json = rawJSON {
            print("  → Raw playlist response (first 1000 chars):")
            print("    \(json.prefix(1000))")
            print("  → Top-level keys: \(topLevelKeys)")
            print("  → Result keys: \(resultKeys)")
        }

        // Detailed decode diagnostics
        if let json = rawJSON {
            testDecodePlaylistManually(data: json.data(using: .utf8)!)
        }

        TestRunner.assert(rawJSON != nil, "integration: raw playlist response received")
        TestRunner.assert(topLevelKeys.contains("stat"), "integration: response has stat key")
        TestRunner.assert(topLevelKeys.contains("result"), "integration: response has result key")

        // Check which key the API uses for playlist items
        let hasItems = resultKeys.contains("items")
        let hasTracks = resultKeys.contains("tracks")
        print("  → result contains 'items': \(hasItems), 'tracks': \(hasTracks)")
        TestRunner.assert(hasItems || hasTracks, "integration: playlist result has items or tracks key")
    }

    private static func testDecodePlaylistManually(data: Data) {
        // Try decoding with full error reporting (not swallowed by try?)
        do {
            let response = try JSONDecoder().decode(PandoraResponse<PlaylistResult>.self, from: data)
            print("  → PandoraResponse decoded, stat=\(response.stat), result=\(response.result != nil ? "present" : "nil")")
            if let result = response.result {
                print("  → items count: \(result.items.count)")
            }
        } catch {
            print("  → PandoraResponse<PlaylistResult> decode error: \(error)")
        }

        // Try decoding result directly
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = dict["result"] {
            do {
                let resultData = try JSONSerialization.data(withJSONObject: result)
                let playlistResult = try JSONDecoder().decode(PlaylistResult.self, from: resultData)
                print("  → Direct PlaylistResult decode OK, items: \(playlistResult.items.count)")
            } catch {
                print("  → Direct PlaylistResult decode error: \(error)")
            }

            // Try decoding a single item
            if let resultDict = result as? [String: Any],
               let items = resultDict["items"] as? [[String: Any]],
               let firstItem = items.first {
                print("  → First item keys: \(Array(firstItem.keys).sorted())")
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: firstItem)
                    let item = try JSONDecoder().decode(PlaylistItem.self, from: itemData)
                    print("  → Single item decode OK: \(item.songName ?? "?")")
                } catch {
                    print("  → Single item decode error: \(error)")
                    // Print value types for debugging
                    for key in ["trackToken", "songRating", "additionalAudioUrl", "audioUrlMap", "adToken"] {
                        if let val = firstItem[key] {
                            print("    \(key): \(type(of: val)) = \(String(describing: val).prefix(100))")
                        } else {
                            print("    \(key): missing")
                        }
                    }
                }
            }
        }
    }

    @discardableResult
    private static func testGetPlaylist(api: PandoraAPI, stationToken: String, sem: DispatchSemaphore) -> [PlaylistItem] {
        var tracks: [PlaylistItem] = []
        var playlistError: Error?

        Task {
            do {
                tracks = try await api.getPlaylist(stationToken: stationToken)
            } catch {
                playlistError = error
            }
            sem.signal()
        }
        sem.wait()

        if let err = playlistError {
            print("  ✗ getPlaylist error: \(err)")
        } else {
            print("  → Got \(tracks.count) tracks")
            if let first = tracks.first {
                print("  → First track: \(first.songName ?? "?") by \(first.artistName ?? "?")")
                print("  → Audio URL: \(first.bestAudioUrl ?? "none")")
            }
        }

        TestRunner.assert(playlistError == nil, "integration: getPlaylist succeeds")
        TestRunner.assert(!tracks.isEmpty, "integration: playlist has tracks")

        // Verify tracks have playable audio URLs
        if let first = tracks.first {
            TestRunner.assert(first.bestAudioUrl != nil, "integration: track has audio URL")
            TestRunner.assert(first.songName != nil, "integration: track has song name")
            TestRunner.assert(first.artistName != nil, "integration: track has artist name")
        }

        // Verify audio URL is reachable (HEAD request)
        if let first = tracks.first {
            testAudioURLReachable(urlString: first.bestAudioUrl, sem: sem)
        }

        return tracks
    }

    private static func testAudioURLReachable(urlString: String?, sem: DispatchSemaphore) {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            TestRunner.assert(false, "integration: audio URL reachable (no URL)")
            return
        }

        var reachable = false
        var httpStatus = 0

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    httpStatus = http.statusCode
                    reachable = (200..<400).contains(http.statusCode)
                }
            } catch {
                print("  ✗ audio URL HEAD request failed: \(error)")
            }
            sem.signal()
        }
        sem.wait()

        print("  → Audio URL: \(urlString.prefix(80))...")
        print("  → HEAD status: \(httpStatus)")
        TestRunner.assert(reachable, "integration: audio URL reachable (HTTP \(httpStatus))")
    }

    private static func testAddFeedback(api: PandoraAPI, trackToken: String?, sem: DispatchSemaphore) {
        guard let token = trackToken else {
            TestRunner.assert(false, "integration: addFeedback (no track token)")
            return
        }

        var feedbackOk = false
        var feedbackError: Error?

        Task {
            do {
                _ = try await api.addFeedback(trackToken: token, isPositive: true)
                feedbackOk = true
            } catch {
                feedbackError = error
            }
            sem.signal()
        }
        sem.wait()

        if let err = feedbackError {
            print("  ✗ addFeedback error: \(err)")
        }
        TestRunner.assert(feedbackOk, "integration: addFeedback (thumbs up) succeeds")
    }

    private static func testTrackFieldCompleteness(tracks: [PlaylistItem]) {
        guard !tracks.isEmpty else { return }

        var allHaveAudio = true
        var allHaveSong = true
        var allHaveArtist = true
        var allHaveToken = true

        for track in tracks {
            if track.bestAudioUrl == nil { allHaveAudio = false }
            if track.songName == nil { allHaveSong = false }
            if track.artistName == nil { allHaveArtist = false }
            if track.trackToken == nil { allHaveToken = false }
        }

        TestRunner.assert(allHaveAudio, "integration: all \(tracks.count) tracks have audio URL")
        TestRunner.assert(allHaveSong, "integration: all tracks have song name")
        TestRunner.assert(allHaveArtist, "integration: all tracks have artist name")
        TestRunner.assert(allHaveToken, "integration: all tracks have track token")

        // Verify no tracks are ads (getPlaylist filters them)
        let adCount = tracks.filter { $0.isAd }.count
        TestRunner.assertEqual(adCount, 0, "integration: no ads in filtered playlist")
    }

    private static func testInvalidStationToken(api: PandoraAPI, sem: DispatchSemaphore) {
        var gotError = false

        Task {
            do {
                _ = try await api.getPlaylist(stationToken: "INVALID_TOKEN_12345")
            } catch {
                gotError = true
                print("  → Expected error for invalid token: \(error)")
            }
            sem.signal()
        }
        sem.wait()

        TestRunner.assert(gotError, "integration: invalid station token returns error")
    }

    private static func testLogoutAndRelogin(api: PandoraAPI, creds: (username: String, password: String), sem: DispatchSemaphore) {
        // Logout
        Task {
            await api.logout()
            sem.signal()
        }
        sem.wait()

        // Verify API calls fail after logout
        var failedAfterLogout = false
        Task {
            do {
                _ = try await api.getStationList()
            } catch {
                failedAfterLogout = true
            }
            sem.signal()
        }
        sem.wait()
        TestRunner.assert(failedAfterLogout, "integration: API call fails after logout")

        // Re-login
        var reloginOk = false
        Task {
            do {
                try await api.partnerLogin()
                try await api.userLogin(username: creds.username, password: creds.password)
                reloginOk = true
            } catch {
                print("  ✗ re-login failed: \(error)")
            }
            sem.signal()
        }
        sem.wait()
        TestRunner.assert(reloginOk, "integration: re-login after logout succeeds")

        // Verify API works again
        var stationsAfterRelogin: [Station] = []
        Task {
            do {
                stationsAfterRelogin = try await api.getStationList()
            } catch {
                print("  ✗ station list after re-login: \(error)")
            }
            sem.signal()
        }
        sem.wait()
        TestRunner.assert(!stationsAfterRelogin.isEmpty, "integration: station list works after re-login")
    }
}
