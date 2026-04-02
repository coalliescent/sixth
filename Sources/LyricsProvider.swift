import Foundation
import os

private let logger = Logger(subsystem: "com.sixth.app", category: "Lyrics")

struct LyricsLine {
    let time: Double  // seconds from start
    let text: String
}

enum LyricsResult {
    case synced([LyricsLine])
    case plain(String)
    case instrumental
    case notFound
}

class LyricsProvider {
    static let shared = LyricsProvider()

    private var cache: [String: LyricsResult] = [:]
    private let cacheLimit = 50

    private init() {}

    private func cacheKey(artist: String, song: String) -> String {
        return "\(artist.lowercased())||\(song.lowercased())"
    }

    func fetchLyrics(song: String, artist: String, album: String,
                     completion: @escaping (LyricsResult) -> Void) {
        let key = cacheKey(artist: artist, song: song)
        if let cached = cache[key] {
            completion(cached)
            return
        }

        fetchFromLRCLIB(song: song, artist: artist, album: album) { [weak self] result in
            if let result = result {
                self?.store(result, forKey: key)
                completion(result)
            } else {
                self?.fetchFromLyricsOvh(song: song, artist: artist) { [weak self] result in
                    let final = result ?? .notFound
                    self?.store(final, forKey: key)
                    completion(final)
                }
            }
        }
    }

    private func store(_ result: LyricsResult, forKey key: String) {
        if cache.count >= cacheLimit {
            // Evict a random entry
            if let evict = cache.keys.first {
                cache.removeValue(forKey: evict)
            }
        }
        cache[key] = result
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - LRCLIB

    private func fetchFromLRCLIB(song: String, artist: String, album: String,
                                  completion: @escaping (LyricsResult?) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: song),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Sixth/1.0", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                logger.debug("LRCLIB error: \(error.localizedDescription, privacy: .public)")
                completion(nil)
                return
            }

            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }

            // Check instrumental
            if json["instrumental"] as? Bool == true {
                completion(.instrumental)
                return
            }

            // Prefer synced lyrics
            if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                let lines = LyricsProvider.parseSyncedLyrics(synced)
                if !lines.isEmpty {
                    completion(.synced(lines))
                    return
                }
            }

            // Fall back to plain
            if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                completion(.plain(plain))
                return
            }

            completion(nil)
        }
        task.resume()
    }

    // MARK: - Lyrics.ovh

    private func fetchFromLyricsOvh(song: String, artist: String,
                                     completion: @escaping (LyricsResult?) -> Void) {
        guard let artistEncoded = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let songEncoded = song.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(artistEncoded)/\(songEncoded)") else {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                logger.debug("Lyrics.ovh error: \(error.localizedDescription, privacy: .public)")
                completion(nil)
                return
            }

            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lyrics = json["lyrics"] as? String, !lyrics.isEmpty else {
                completion(nil)
                return
            }

            completion(.plain(lyrics))
        }
        task.resume()
    }

    // MARK: - LRC Parser

    static func parseSyncedLyrics(_ raw: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }

            // Match [mm:ss.ff] text
            guard let bracket = trimmed.firstIndex(of: "]") else { continue }
            let inside = trimmed[trimmed.index(after: trimmed.startIndex)..<bracket]
            let parts = inside.split(separator: ":", maxSplits: 2)
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { continue }

            let time = minutes * 60.0 + seconds
            let textStart = trimmed.index(after: bracket)
            let text = String(trimmed[textStart...]).trimmingCharacters(in: .whitespaces)

            // Skip empty lines and metadata tags like [ti:], [ar:], etc.
            if text.isEmpty { continue }

            lines.append(LyricsLine(time: time, text: text))
        }
        return lines.sorted { $0.time < $1.time }
    }
}
