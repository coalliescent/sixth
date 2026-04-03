import Foundation

struct TrackHistoryTests {
    static func runAll() {
        testAddEntry()
        testMaxEntries()
        testMostRecentFirst()
        testUpdateRating()
        testClear()
        testCodableRoundTrip()
        testInitFromPlaylistItem()
        testDuplicateTracksAllowed()
    }

    static func testAddEntry() {
        let history = TrackHistory(entries: [])
        let entry = HistoryEntry(songName: "Song", artistName: "Artist", albumName: "Album",
                                 albumArtUrl: "https://example.com/art.jpg", songRating: 1,
                                 trackToken: "token1", stationId: "station1", timestamp: Date())
        history.add(entry)
        TestRunner.assertEqual(history.entries.count, 1, "add entry — count is 1")
        TestRunner.assertEqual(history.entries[0].songName, "Song", "add entry — songName")
        TestRunner.assertEqual(history.entries[0].trackToken, "token1", "add entry — trackToken")
    }

    static func testMaxEntries() {
        let history = TrackHistory(entries: [])
        for i in 0..<110 {
            let entry = HistoryEntry(songName: "Song \(i)", artistName: "Artist", albumName: "Album",
                                     albumArtUrl: nil, songRating: 0, trackToken: "token\(i)",
                                     stationId: nil, timestamp: Date())
            history.add(entry)
        }
        TestRunner.assertEqual(history.entries.count, 100, "max entries — capped at 100")
        TestRunner.assertEqual(history.entries[0].songName, "Song 109", "max entries — most recent first")
    }

    static func testMostRecentFirst() {
        let history = TrackHistory(entries: [])
        for i in 0..<3 {
            let entry = HistoryEntry(songName: "Song \(i)", artistName: "Artist", albumName: "Album",
                                     albumArtUrl: nil, songRating: 0, trackToken: "token\(i)",
                                     stationId: nil, timestamp: Date())
            history.add(entry)
        }
        TestRunner.assertEqual(history.entries[0].songName, "Song 2", "most recent first — index 0")
        TestRunner.assertEqual(history.entries[1].songName, "Song 1", "most recent first — index 1")
        TestRunner.assertEqual(history.entries[2].songName, "Song 0", "most recent first — index 2")
    }

    static func testUpdateRating() {
        let history = TrackHistory(entries: [])
        let entry = HistoryEntry(songName: "Song", artistName: "Artist", albumName: "Album",
                                 albumArtUrl: nil, songRating: 0, trackToken: "token1",
                                 stationId: nil, timestamp: Date())
        history.add(entry)
        history.updateRating(trackToken: "token1", newRating: 1)
        TestRunner.assertEqual(history.entries[0].songRating, 1, "update rating — set to 1")
        history.updateRating(trackToken: "token1", newRating: 0)
        TestRunner.assertEqual(history.entries[0].songRating, 0, "update rating — set back to 0")
        history.updateRating(trackToken: "nonexistent", newRating: 1)
        TestRunner.assertEqual(history.entries[0].songRating, 0, "update rating — no-op for missing token")
    }

    static func testClear() {
        let history = TrackHistory(entries: [])
        for i in 0..<5 {
            let entry = HistoryEntry(songName: "Song \(i)", artistName: "Artist", albumName: "Album",
                                     albumArtUrl: nil, songRating: 0, trackToken: "token\(i)",
                                     stationId: nil, timestamp: Date())
            history.add(entry)
        }
        history.clear()
        TestRunner.assertEqual(history.entries.count, 0, "clear — empty after clear")
    }

    static func testCodableRoundTrip() {
        let entry = HistoryEntry(songName: "Test Song", artistName: "Test Artist",
                                 albumName: "Test Album", albumArtUrl: "https://example.com/art.jpg",
                                 songRating: 1, trackToken: "roundtrip_token",
                                 stationId: "station42", timestamp: Date(timeIntervalSince1970: 1000000))
        let entries = [entry]
        let data = try! JSONEncoder().encode(entries)
        let decoded = try! JSONDecoder().decode([HistoryEntry].self, from: data)
        TestRunner.assertEqual(decoded.count, 1, "codable round trip — count")
        TestRunner.assertEqual(decoded[0].songName, "Test Song", "codable round trip — songName")
        TestRunner.assertEqual(decoded[0].artistName, "Test Artist", "codable round trip — artistName")
        TestRunner.assertEqual(decoded[0].albumName, "Test Album", "codable round trip — albumName")
        TestRunner.assertEqual(decoded[0].albumArtUrl, "https://example.com/art.jpg", "codable round trip — albumArtUrl")
        TestRunner.assertEqual(decoded[0].songRating, 1, "codable round trip — songRating")
        TestRunner.assertEqual(decoded[0].trackToken, "roundtrip_token", "codable round trip — trackToken")
        TestRunner.assertEqual(decoded[0].stationId, "station42", "codable round trip — stationId")
        TestRunner.assertEqual(decoded[0].timestamp, Date(timeIntervalSince1970: 1000000), "codable round trip — timestamp")
    }

    static func testInitFromPlaylistItem() {
        let item = PlaylistItem(trackToken: "tk123", artistName: "The Artist",
                                albumName: "The Album", songName: "The Song",
                                songRating: 1, albumArtUrl: "https://example.com/art.jpg",
                                additionalAudioUrl: nil, audioUrlMap: nil,
                                songDetailUrl: nil, stationId: "st456",
                                songIdentity: nil, adToken: nil)
        let entry = HistoryEntry(from: item)
        TestRunner.assertEqual(entry.songName, "The Song", "init from PlaylistItem — songName")
        TestRunner.assertEqual(entry.artistName, "The Artist", "init from PlaylistItem — artistName")
        TestRunner.assertEqual(entry.albumName, "The Album", "init from PlaylistItem — albumName")
        TestRunner.assertEqual(entry.albumArtUrl, "https://example.com/art.jpg", "init from PlaylistItem — albumArtUrl")
        TestRunner.assertEqual(entry.songRating, 1, "init from PlaylistItem — songRating")
        TestRunner.assertEqual(entry.trackToken, "tk123", "init from PlaylistItem — trackToken")
        TestRunner.assertEqual(entry.stationId, "st456", "init from PlaylistItem — stationId")
    }

    static func testDuplicateTracksAllowed() {
        let history = TrackHistory(entries: [])
        let entry1 = HistoryEntry(songName: "Song", artistName: "Artist", albumName: "Album",
                                  albumArtUrl: nil, songRating: 0, trackToken: "same_token",
                                  stationId: nil, timestamp: Date())
        let entry2 = HistoryEntry(songName: "Song", artistName: "Artist", albumName: "Album",
                                  albumArtUrl: nil, songRating: 0, trackToken: "same_token",
                                  stationId: nil, timestamp: Date())
        history.add(entry1)
        history.add(entry2)
        TestRunner.assertEqual(history.entries.count, 1, "consecutive duplicate — deduplicated")

        // Different track after same token is still added
        let entry3 = HistoryEntry(songName: "Other", artistName: "Artist", albumName: "Album",
                                  albumArtUrl: nil, songRating: 0, trackToken: "different_token",
                                  stationId: nil, timestamp: Date())
        history.add(entry3)
        TestRunner.assertEqual(history.entries.count, 2, "different track — added normally")
    }
}
