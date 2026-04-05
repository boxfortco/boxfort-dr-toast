import SwiftUI

struct LobbyView: View {
    @Bindable var model: HostViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if model.gameState == "deal_phase" {
                    dealPhaseBanner
                }

                roomAndShareSection

                playersSection

                if model.gameState == "lobby" {
                    startButton
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 40 : 20
    }

    private var roomAndShareSection: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 32) {
                    roomCodeBlock
                    qrAndShareColumn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 24) {
                    roomCodeBlock
                    qrAndShareColumn
                }
            }
        }
    }

    private var roomCodeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Room code")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(model.roomCode.isEmpty ? "····" : model.roomCode)
                .font(.system(size: roomCodeFontSize, weight: .bold, design: .monospaced))
                .tracking(10)
                .foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.32))
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.72))
                        .shadow(color: .black.opacity(0.06), radius: 0, x: 4, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                        )
                        .foregroundStyle(Color.brown.opacity(0.35))
                )
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 320 : .infinity, alignment: .leading)
    }

    private var roomCodeFontSize: CGFloat {
        horizontalSizeClass == .regular ? 64 : 52
    }

    private var qrAndShareColumn: some View {
        VStack(spacing: 16) {
            if let url = model.shareURL {
                VStack(spacing: 10) {
                    QRCodeImage(url: url, dimension: horizontalSizeClass == .regular ? 200 : 180)
                    Text("Scan to join")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.55))
                )

                ShareLink(
                    item: url,
                    subject: Text("Join my BoxFort game"),
                    message: Text("Join my BoxFort game! \(url.absoluteString)")
                ) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.45, green: 0.32, blue: 0.14))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var dealPhaseBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Round ready", systemImage: "checkmark.circle.fill")
                .font(.headline)
            Text("Secret words are on each phone. Take turns answering the prompt out loud.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let prompt = model.currentPrompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.body.weight(.medium))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.6))
                    )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.green.opacity(0.35))
        )
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Players")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(model.players.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.5)))
            }

            if model.players.isEmpty {
                Text("Waiting for phones to join…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.players) { p in
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.brown.opacity(0.75))
                        Text(p.displayName)
                            .font(.body.weight(.medium))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.45))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startButton: some View {
        VStack(spacing: 12) {
            if let err = model.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if !model.connectionHint.isEmpty {
                Text(model.connectionHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await model.startGame() }
            } label: {
                if model.isStartingGame {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Start game")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.2, green: 0.45, blue: 0.32))
            .disabled(!model.canStartGame)

            Text("Need at least 3 players. AI will cook up a fresh prompt and words.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    LobbyView(model: HostViewModel())
}
