import Foundation
import Observation

@Observable
@MainActor
final class HostViewModel {
    private let client = SupabaseRESTClient()
    private var pollTask: Task<Void, Never>?

    var roomCode: String = ""
    var gameId: UUID?
    var gameState: String = "lobby"
    var currentPrompt: String?
    var players: [PlayerRecord] = []
    var connectionHint: String = ""
    var lastError: String?
    var isStartingGame = false

    var shareURL: URL? {
        guard roomCode.count == 4 else { return nil }
        return BoxFortConfig.joinURL(roomCode: roomCode)
    }

    var canStartGame: Bool {
        players.count >= 3 && gameState == "lobby" && gameId != nil && !isStartingGame
    }

    func onAppear() {
        Task { await startOrResumeSession() }
    }

    func onDisappear() {
        pollTask?.cancel()
        pollTask = nil
    }

    func startGame() async {
        guard let gameId, canStartGame else { return }
        isStartingGame = true
        lastError = nil
        defer { isStartingGame = false }
        do {
            try await client.invokeGenerateRound(gameId: gameId)
            await refreshLobby(gameId: gameId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startOrResumeSession() async {
        lastError = nil
        if BoxFortConfig.supabaseAnonKey == "YOUR_ANON_KEY" {
            connectionHint = "Set BoxFortConfig.swift with your Supabase URL and anon key."
            return
        }

        if BoxFortConfig.webJoinBaseURL.host == "YOUR_DEPLOYMENT.example"
            || BoxFortConfig.webJoinBaseURL.host?.contains("YOUR_DEPLOYMENT") == true
        {
            connectionHint = "Set BoxFortConfig.webJoinBaseURL to your live web app URL for sharing and QR."
        }

        do {
            let code = try await ensureRoomCode()
            roomCode = code
            let game = try await client.createGame(roomCode: code)
            gameId = game.id
            gameState = game.state
            currentPrompt = game.currentPrompt
            if connectionHint.isEmpty {
                connectionHint = "Share the link or QR so players can join on their phones."
            }
            startPolling(gameId: game.id)
            await refreshLobby(gameId: game.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func ensureRoomCode() async throws -> String {
        if !roomCode.isEmpty, roomCode.count == 4 { return roomCode }
        return Self.generateRoomCode()
    }

    private func startPolling(gameId: UUID) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                await refreshLobby(gameId: gameId)
            }
        }
    }

    private func refreshLobby(gameId: UUID) async {
        do {
            async let gameTask = client.fetchGame(gameId: gameId)
            async let playersTask = client.fetchPlayers(gameId: gameId)
            let (game, pl) = try await (gameTask, playersTask)
            gameState = game.state
            currentPrompt = game.currentPrompt
            players = pl
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func generateRoomCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        return String((0 ..< 4).map { _ in letters.randomElement()! })
    }
}
