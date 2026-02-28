import Foundation

// MARK: - Pandora API Response Models

struct PandoraResponse<T: Decodable>: Decodable {
    let stat: String
    let result: T?
    let message: String?
    let code: Int?

    var isOk: Bool { stat == "ok" }

    enum CodingKeys: String, CodingKey {
        case stat, result, message, code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stat = try container.decode(String.self, forKey: .stat)
        result = try? container.decodeIfPresent(T.self, forKey: .result)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        code = try? container.decodeIfPresent(Int.self, forKey: .code)
    }
}

struct PartnerLoginResult: Decodable {
    let partnerId: String
    let partnerAuthToken: String
    let syncTime: String // encrypted, needs decryption
    let stationCreationAdUrl: String?
    let partnerType: String?
}

struct UserLoginResult: Decodable {
    let userId: String
    let userAuthToken: String
    let canListen: Bool?
    let hasAudioAds: Bool?
    let stationCreationAdUrl: String?
    let listeningTimeoutMinutes: String?
}

struct StationListResult: Decodable {
    let stations: [Station]
    let checksum: String?
}

struct Station: Decodable, Identifiable {
    let stationId: String
    let stationName: String
    let stationToken: String
    let isQuickMix: Bool?
    let artUrl: String?

    var id: String { stationId }
}

struct PlaylistResult: Decodable {
    let items: [PlaylistItem]

    enum CodingKeys: String, CodingKey {
        case items, tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // API sometimes returns "items", sometimes "tracks"
        if let items = try? c.decode([PlaylistItem].self, forKey: .items) {
            self.items = items
        } else {
            self.items = try c.decode([PlaylistItem].self, forKey: .tracks)
        }
    }
}

struct PlaylistItem: Decodable {
    let trackToken: String?
    let artistName: String?
    let albumName: String?
    let songName: String?
    let songRating: Int?
    let albumArtUrl: String?
    let additionalAudioUrl: [String]?
    let audioUrlMap: AudioUrlMap?
    let songDetailUrl: String?
    let stationId: String?
    let songIdentity: String?
    let adToken: String?

    var isAd: Bool { adToken != nil }

    enum CodingKeys: String, CodingKey {
        case trackToken, artistName, albumName, songName, songRating
        case albumArtUrl, additionalAudioUrl, audioUrlMap, songDetailUrl
        case stationId, songIdentity, adToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackToken = try? c.decodeIfPresent(String.self, forKey: .trackToken)
        artistName = try? c.decodeIfPresent(String.self, forKey: .artistName)
        albumName = try? c.decodeIfPresent(String.self, forKey: .albumName)
        songName = try? c.decodeIfPresent(String.self, forKey: .songName)
        songRating = try? c.decodeIfPresent(Int.self, forKey: .songRating)
        albumArtUrl = try? c.decodeIfPresent(String.self, forKey: .albumArtUrl)
        audioUrlMap = try? c.decodeIfPresent(AudioUrlMap.self, forKey: .audioUrlMap)
        songDetailUrl = try? c.decodeIfPresent(String.self, forKey: .songDetailUrl)
        stationId = try? c.decodeIfPresent(String.self, forKey: .stationId)
        songIdentity = try? c.decodeIfPresent(String.self, forKey: .songIdentity)
        adToken = try? c.decodeIfPresent(String.self, forKey: .adToken)
        // API returns either a single string or an array of strings
        if let arr = try? c.decodeIfPresent([String].self, forKey: .additionalAudioUrl) {
            additionalAudioUrl = arr
        } else if let single = try? c.decodeIfPresent(String.self, forKey: .additionalAudioUrl) {
            additionalAudioUrl = [single]
        } else {
            additionalAudioUrl = nil
        }
    }

    // Memberwise init for tests
    init(trackToken: String?, artistName: String?, albumName: String?, songName: String?,
         songRating: Int?, albumArtUrl: String?, additionalAudioUrl: [String]?,
         audioUrlMap: AudioUrlMap?, songDetailUrl: String?, stationId: String?,
         songIdentity: String?, adToken: String?) {
        self.trackToken = trackToken; self.artistName = artistName
        self.albumName = albumName; self.songName = songName
        self.songRating = songRating; self.albumArtUrl = albumArtUrl
        self.additionalAudioUrl = additionalAudioUrl; self.audioUrlMap = audioUrlMap
        self.songDetailUrl = songDetailUrl; self.stationId = stationId
        self.songIdentity = songIdentity; self.adToken = adToken
    }

    var bestAudioUrl: String? {
        // Prefer high quality AAC, then medium, then additional URLs
        if let map = audioUrlMap {
            if let high = map.highQuality?.audioUrl { return high }
            if let med = map.mediumQuality?.audioUrl { return med }
            if let low = map.lowQuality?.audioUrl { return low }
        }
        return additionalAudioUrl?.first
    }
}

struct AudioUrlMap: Decodable {
    let highQuality: AudioUrl?
    let mediumQuality: AudioUrl?
    let lowQuality: AudioUrl?
}

struct AudioUrl: Decodable {
    let bitrate: String?
    let encoding: String?
    let audioUrl: String?
    let protocol_: String?

    enum CodingKeys: String, CodingKey {
        case bitrate, encoding, audioUrl
        case protocol_ = "protocol"
    }
}

struct AddFeedbackResult: Decodable {
    let feedbackId: String?
    let isPositive: Bool?
}

struct EmptyResult: Decodable {}

// MARK: - Pandora API Error

enum PandoraError: Error, CustomStringConvertible {
    case partnerLoginFailed(String)
    case userLoginFailed(String)
    case apiError(code: Int, message: String)
    case encryptionError(String)
    case networkError(Error)
    case invalidResponse
    case noTracksAvailable
    case notLoggedIn

    static let invalidAuthTokenCode = 1001

    var description: String {
        switch self {
        case .partnerLoginFailed(let msg): return "Partner login failed: \(msg)"
        case .userLoginFailed(let msg): return "User login failed: \(msg)"
        case .apiError(let code, let msg): return "API error \(code): \(msg)"
        case .encryptionError(let msg): return "Encryption error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .invalidResponse: return "Invalid API response"
        case .noTracksAvailable: return "No tracks available"
        case .notLoggedIn: return "Not logged in"
        }
    }
}

// MARK: - Pandora Partner Config

struct PandoraPartner {
    static let username = "android"
    static let password = "AC7IBG09A3DTSYM4R41UJWL07VLN8JI7"
    static let deviceModel = "android-generic"
    static let version = "5"
    static let encryptKey = "6#26FRL$ZWD"
    static let decryptKey = "R=U!LH$O2B#"
    static let baseURL = "https://tuner.pandora.com/services/json/"
}
