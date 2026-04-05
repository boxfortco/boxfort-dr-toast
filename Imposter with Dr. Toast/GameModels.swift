import Foundation

struct GameRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var roomCode: String
    var state: String
    var currentPrompt: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomCode = "room_code"
        case state
        case currentPrompt = "current_prompt"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PlayerRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let gameId: UUID
    var displayName: String
    var role: String?
    var secretWord: String?
    var score: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case gameId = "game_id"
        case displayName = "display_name"
        case role
        case secretWord = "secret_word"
        case score
        case createdAt = "created_at"
    }
}
