import Foundation

#if TESTING
// For testing, allow injection of a custom URLSession
var pandoraURLSession: URLSession = .shared
#endif

actor PandoraAPI {
    private var partnerId: String?
    private var partnerAuthToken: String?
    private var syncTime: Int?
    private var syncTimeBase: Int? // local time when sync was received
    private var userId: String?
    private var userAuthToken: String?

    private let session: URLSession

    var isLoggedIn: Bool { userAuthToken != nil }

    init(session: URLSession? = nil) {
        #if TESTING
        self.session = session ?? pandoraURLSession
        #else
        self.session = session ?? .shared
        #endif
    }

    // MARK: - Current sync time (adjusted for clock drift)

    private var currentSyncTime: Int {
        guard let base = syncTime, let localBase = syncTimeBase else { return 0 }
        let elapsed = Int(Date().timeIntervalSince1970) - localBase
        return base + elapsed
    }

    // MARK: - Partner Login

    func partnerLogin() async throws {
        let body: [String: Any] = [
            "username": PandoraPartner.username,
            "password": PandoraPartner.password,
            "deviceModel": PandoraPartner.deviceModel,
            "version": PandoraPartner.version,
            "includeUrls": true
        ]

        let url = buildURL(method: "auth.partnerLogin")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, _) = try await session.data(for: request)

        #if DEBUG
        if let debugStr = String(data: data, encoding: .utf8) {
            print("[API auth.partnerLogin] \(debugStr.prefix(500))")
        }
        #endif

        let response = try JSONDecoder().decode(PandoraResponse<PartnerLoginResult>.self, from: data)

        guard response.isOk, let result = response.result else {
            throw PandoraError.partnerLoginFailed(response.message ?? "Unknown error")
        }

        partnerId = result.partnerId
        partnerAuthToken = result.partnerAuthToken
        syncTimeBase = Int(Date().timeIntervalSince1970)

        // Decrypt sync time
        guard let decryptedSync = BlowfishCrypto.decryptSyncTime(result.syncTime, key: PandoraPartner.decryptKey) else {
            throw PandoraError.encryptionError("Failed to decrypt sync time")
        }
        syncTime = decryptedSync
    }

    // MARK: - User Login

    func userLogin(username: String, password: String) async throws {
        guard let pToken = partnerAuthToken, let pId = partnerId else {
            throw PandoraError.notLoggedIn
        }

        let body: [String: Any] = [
            "loginType": "user",
            "username": username,
            "password": password,
            "partnerAuthToken": pToken,
            "syncTime": currentSyncTime
        ]

        let data = try await encryptedRequest(
            method: "auth.userLogin",
            body: body,
            partnerIdParam: pId,
            authToken: pToken
        )

        let response = try JSONDecoder().decode(PandoraResponse<UserLoginResult>.self, from: data)

        guard response.isOk, let result = response.result else {
            let msg = response.message ?? "Unknown error"
            throw PandoraError.userLoginFailed(msg)
        }

        userId = result.userId
        userAuthToken = result.userAuthToken
    }

    // MARK: - Get Station List

    func getStationList() async throws -> [Station] {
        var body = authBody()
        body["includeStationArtUrl"] = true
        let data = try await authenticatedRequest(method: "user.getStationList", body: body)
        let response = try JSONDecoder().decode(PandoraResponse<StationListResult>.self, from: data)

        guard response.isOk, let result = response.result else {
            throw apiError(from: response)
        }

        return result.stations
    }

    // MARK: - Get Playlist

    func getPlaylist(stationToken: String) async throws -> [PlaylistItem] {
        var body = authBody()
        body["stationToken"] = stationToken
        body["additionalAudioUrl"] = "HTTP_192_MP3,HTTP_128_MP3"

        let data = try await authenticatedRequest(method: "station.getPlaylist", body: body)
        let response = try JSONDecoder().decode(PandoraResponse<PlaylistResult>.self, from: data)

        guard response.isOk, let result = response.result else {
            throw apiError(from: response)
        }

        return result.items.filter { !$0.isAd }
    }

    // MARK: - Raw Station List (for debugging/testing)

    func getRawStationList() async throws -> Data {
        var body = authBody()
        body["includeStationArtUrl"] = true
        return try await authenticatedRequest(method: "user.getStationList", body: body)
    }

    // MARK: - Raw Playlist (for debugging/testing)

    func getRawPlaylist(stationToken: String) async throws -> Data {
        var body = authBody()
        body["stationToken"] = stationToken
        body["additionalAudioUrl"] = "HTTP_192_MP3,HTTP_128_MP3"
        return try await authenticatedRequest(method: "station.getPlaylist", body: body)
    }

    // MARK: - Add Feedback (thumbs up/down)

    func addFeedback(trackToken: String, isPositive: Bool) async throws -> String? {
        var body = authBody()
        body["trackToken"] = trackToken
        body["isPositive"] = isPositive

        let data = try await authenticatedRequest(method: "station.addFeedback", body: body)
        let response = try JSONDecoder().decode(PandoraResponse<AddFeedbackResult>.self, from: data)

        guard response.isOk else {
            throw apiError(from: response)
        }
        return response.result?.feedbackId
    }

    // MARK: - Delete Feedback (remove thumbs up/down)

    func deleteFeedback(feedbackId: String) async throws {
        var body = authBody()
        body["feedbackId"] = feedbackId

        let data = try await authenticatedRequest(method: "station.deleteFeedback", body: body)
        let response = try JSONDecoder().decode(PandoraResponse<EmptyResult>.self, from: data)

        guard response.isOk else {
            throw apiError(from: response)
        }
    }

    // MARK: - Logout

    func logout() {
        partnerId = nil
        partnerAuthToken = nil
        syncTime = nil
        syncTimeBase = nil
        userId = nil
        userAuthToken = nil
    }

    // MARK: - Helpers

    private func authBody() -> [String: Any] {
        return [
            "userAuthToken": userAuthToken ?? "",
            "syncTime": currentSyncTime
        ]
    }

    private func authenticatedRequest(method: String, body: [String: Any]) async throws -> Data {
        guard let pId = partnerId, let uToken = userAuthToken else {
            throw PandoraError.notLoggedIn
        }
        return try await encryptedRequest(
            method: method,
            body: body,
            partnerIdParam: pId,
            authToken: uToken,
            userId: userId
        )
    }

    private func encryptedRequest(
        method: String,
        body: [String: Any],
        partnerIdParam: String,
        authToken: String,
        userId: String? = nil
    ) async throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw PandoraError.encryptionError("Failed to serialize JSON")
        }

        guard let encrypted = BlowfishCrypto.encrypt(jsonString, key: PandoraPartner.encryptKey) else {
            throw PandoraError.encryptionError("Failed to encrypt request body")
        }

        var url = buildURL(method: method)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "partner_id", value: partnerIdParam))
        queryItems.append(URLQueryItem(name: "auth_token", value: authToken))
        if let uid = userId {
            queryItems.append(URLQueryItem(name: "user_id", value: uid))
        }
        components.queryItems = queryItems
        url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = encrypted.data(using: .utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, _) = try await session.data(for: request)

        #if DEBUG
        if let debugStr = String(data: data, encoding: .utf8) {
            print("[API \(method)] \(debugStr.prefix(500))")
        }
        #endif

        return data
    }

    private func buildURL(method: String) -> URL {
        var components = URLComponents(string: PandoraPartner.baseURL)!
        components.queryItems = [URLQueryItem(name: "method", value: method)]
        return components.url!
    }

    private func apiError<T>(from response: PandoraResponse<T>) -> PandoraError {
        if let code = response.code, let msg = response.message {
            return .apiError(code: code, message: msg)
        }
        return .invalidResponse
    }
}
