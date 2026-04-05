import Foundation

/// Replace placeholders with your Supabase project URL and anon key (Project Settings → API).
/// Set `webJoinBaseURL` to your deployed Next.js origin (no trailing slash), e.g. `https://boxfort.vercel.app`
enum BoxFortConfig: Sendable {
    nonisolated static let supabaseURL = URL(string: "https://YOUR_PROJECT_ID.supabase.co")!
    nonisolated static let supabaseAnonKey = "YOUR_ANON_KEY"

    /// Base URL for player join links and QR codes (scheme + host, optional path; no trailing slash).
    nonisolated static let webJoinBaseURL = URL(string: "https://YOUR_DEPLOYMENT.example")!

    static func joinURL(roomCode: String) -> URL? {
        var base = webJoinBaseURL.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "code", value: roomCode)]
        return components?.url
    }
}
