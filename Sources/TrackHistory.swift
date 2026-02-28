import Foundation

struct HistoryEntry: Codable, Equatable {
    let songName: String
    let artistName: String
    let albumName: String
    let albumArtUrl: String?
    var songRating: Int
    let trackToken: String
    let stationId: String?
    let timestamp: Date

    init(from track: PlaylistItem) {
        self.songName = track.songName ?? "Unknown"
        self.artistName = track.artistName ?? "Unknown"
        self.albumName = track.albumName ?? "Unknown"
        self.albumArtUrl = track.albumArtUrl
        self.songRating = track.songRating ?? 0
        self.trackToken = track.trackToken ?? ""
        self.stationId = track.stationId
        self.timestamp = Date()
    }

    init(songName: String, artistName: String, albumName: String,
         albumArtUrl: String?, songRating: Int, trackToken: String,
         stationId: String?, timestamp: Date) {
        self.songName = songName
        self.artistName = artistName
        self.albumName = albumName
        self.albumArtUrl = albumArtUrl
        self.songRating = songRating
        self.trackToken = trackToken
        self.stationId = stationId
        self.timestamp = timestamp
    }
}

class TrackHistory {
    static let shared = TrackHistory()

    private(set) var entries: [HistoryEntry] = []
    private let persist: Bool

    init() {
        self.persist = true
        load()
    }

    init(entries: [HistoryEntry]) {
        self.persist = false
        self.entries = entries
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 100 {
            entries = Array(entries.prefix(100))
        }
        save()
    }

    func updateRating(trackToken: String, newRating: Int) {
        if let idx = entries.firstIndex(where: { $0.trackToken == trackToken }) {
            entries[idx].songRating = newRating
            save()
        }
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard persist else { return }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "trackHistory")
        }
    }

    private func load() {
        guard persist,
              let data = UserDefaults.standard.data(forKey: "trackHistory"),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
