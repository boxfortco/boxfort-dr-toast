import Foundation

/// Supabase project (Project Settings → API). Publishable key is safe in client apps; prefer xcconfig + gitignore for forks.
/// `webJoinBaseURL` must match your deployed Next.js origin (no trailing slash).
enum BoxFortConfig: Sendable {
    nonisolated static let supabaseURL = URL(string: "https://ptikdxiaypmmvvzpbzea.supabase.co")!
    nonisolated static let supabaseAnonKey =
        "sb_publishable_lmlGE-jS2t0bB8OxJYq2Zw_bFMvxgP_"

    /// Base URL for player join links and QR codes (scheme + host, optional path; no trailing slash).
    nonisolated static let webJoinBaseURL = URL(string: "https://web-beta-khaki-33.vercel.app")!

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
