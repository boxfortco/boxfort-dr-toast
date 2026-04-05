import Foundation

/// Minimal PostgREST client for the host app (create game, list players).
/// Uses the public anon key; tighten auth before shipping broadly.
actor SupabaseRESTClient {
    private let baseURL: URL
    private let anonKey: String
    private let decoder: JSONDecoder

    init(baseURL: URL = BoxFortConfig.supabaseURL, anonKey: String = BoxFortConfig.supabaseAnonKey) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let str = try c.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: str)
        }
        self.decoder = dec
    }

    private func applyAuth(to req: inout URLRequest) {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
    }

    func createGame(roomCode: String) async throws -> GameRecord {
        let url = baseURL.appendingPathComponent("rest/v1/games")
        let payload: [String: Any] = [
            "room_code": roomCode,
            "state": "lobby",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyAuth(to: &req)
        req.httpBody = data
        let (respData, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response: resp, data: respData)
        let games = try decoder.decode([GameRecord].self, from: respData)
        guard let g = games.first else {
            throw URLError(.cannotParseResponse)
        }
        return g
    }

    func fetchGame(gameId: UUID) async throws -> GameRecord {
        let gamesURL = baseURL.appendingPathComponent("rest/v1/games")
        var comps = URLComponents(url: gamesURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(gameId.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "*"),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response: resp, data: data)
        let games = try decoder.decode([GameRecord].self, from: data)
        guard let g = games.first else {
            throw URLError(.cannotParseResponse)
        }
        return g
    }

    func fetchPlayers(gameId: UUID) async throws -> [PlayerRecord] {
        let playersURL = baseURL.appendingPathComponent("rest/v1/players")
        var comps = URLComponents(url: playersURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "game_id", value: "eq.\(gameId.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response: resp, data: data)
        return try decoder.decode([PlayerRecord].self, from: data)
    }

    /// Invokes the `generate-round` Edge Function (Anthropic + role assignment).
    func invokeGenerateRound(gameId: UUID) async throws {
        let url = baseURL.appendingPathComponent("functions/v1/generate-round")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = ["game_id": gameId.uuidString.lowercased()]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response: resp, data: data)
    }

    private func throwIfNeeded(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "SupabaseREST",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "HTTP \(http.statusCode)" : text]
            )
        }
    }
}
