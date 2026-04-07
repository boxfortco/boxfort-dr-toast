import SwiftUI
import UIKit

// MARK: - Hub hero imagery (voting / resolution / reveal — aligns with web ~90vw presence)

private enum HubHeroImageMetrics {
    /// Avoid `UIScreen.main` (deprecated iOS 26); fall back to a typical phone size only before any window exists (e.g. previews).
    private static var referenceBounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let b = scenes.first?.screen.bounds { return b }
        return CGRect(x: 0, y: 0, width: 393, height: 852)
    }

    static func maxHeight(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let b = referenceBounds
        let shortSide = min(b.width, b.height)
        let longSide = max(b.width, b.height)
        if horizontalSizeClass == .regular {
            return min(longSide * 0.42, 600)
        }
        return min(shortSide * 0.90, 480)
    }

    /// Clue / round object art — large but slightly tighter than full character polaroids.
    static func roundObjectMaxSide(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        let h = maxHeight(horizontalSizeClass: horizontalSizeClass)
        return min(h * 0.78, horizontalSizeClass == .regular ? 340 : 300)
    }
}

struct LobbyView: View {
    @Bindable var model: HostViewModel
    /// Owned by `ContentView` so the name field is not under the same `LobbyView` / `@Observable` subtree as the hub.
    @Binding var hostNameSheetPresented: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    /// Hub-only: round image stays hidden until the host press-and-holds (reduces imposter-host peeking).
    @State private var hostRevealingRoundImage = false
    @State private var showingHubMenu = false
    @State private var showCopiedLinkMessage = false
    @State private var showdownCountdown = 5
    @State private var isShowdownPulsing = false
    @State private var lastOutcomeAudioRound: Int?
    @State private var hubRoleRevealSeenRound: Int?
    /// QR uses Core Image; generate only after the host asks so the hub scrolls smoothly on load.
    @State private var showInviteQRCode = false

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                let containerW = max(geo.size.width, 1)
                ScrollView {
                    hubScrollColumn
                        .frame(maxWidth: hubContentMaxWidth(containerWidth: containerW))
                        .frame(maxWidth: .infinity)
                        .frame(width: containerW, alignment: .center)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.gameState) { oldState, newState in
                    if oldState == "lobby", newState != "lobby" {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            proxy.scrollTo("hubTop", anchor: .top)
                        }
                    }
                    if oldState == "voting", newState == "resolution" {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            proxy.scrollTo("hubTop", anchor: .top)
                        }
                    }
                }
                .onChange(of: model.showdownPending) { _, pending in
                    guard pending else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo("hubShowdown", anchor: .top)
                        }
                    }
                }
                .frame(width: containerW, height: geo.size.height)
            }
        }
        .task {
            await model.ensureHubSession()
        }
        .onAppear {
            BoxFortAudio.shared.syncFromSettings()
            BoxFortAudio.shared.ensureBackgroundMusicIfIdle()
            syncStateAudio()
        }
        .onDisappear { model.onDisappear() }
        .task(id: model.showdownPending) {
            if model.showdownPending {
                await runShowdownCountdown()
            } else {
                showdownCountdown = 5
                isShowdownPulsing = false
            }
        }
        .onChange(of: model.showdownPending) { _, _ in
            syncStateAudio()
        }
        .onChange(of: model.gameState) { _, _ in syncStateAudio() }
        .onChange(of: model.showdownResolved) { _, _ in syncStateAudio() }
        .onChange(of: model.lastImposterCaught) { _, _ in syncStateAudio() }
        .onChange(of: model.imposterWordGuessed) { _, _ in syncStateAudio() }
        .onChange(of: model.roundNumber) { _, _ in syncStateAudio() }
        .onChange(of: model.roundNumber) { _, _ in
            if model.gameState == "deal" {
                hubRoleRevealSeenRound = nil
            }
        }
        .onChange(of: model.roomCode) { _, _ in
            showInviteQRCode = false
        }
        .sheet(isPresented: $showingHubMenu) {
            HubMenuSheet()
        }
        .alert("Invite link copied", isPresented: $showCopiedLinkMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Paste it into Messages, WhatsApp, or anywhere you share with players.")
        }
    }

    private var isPromptLike: Bool {
        model.gameState == "prompt" || model.gameState == "deal"
    }

    private var horizontalPadding: CGFloat {
        // Extra inset on compact so cream paper + pin shadows (drawn outside layout bounds) stay on-screen,
        // and a sliver of corkboard stays visible past the white cards.
        horizontalSizeClass == .regular ? 40 : 42
    }

    /// Responsive hub column width from the live container (iPad landscape grows with the window; iPhone stays capped for readability).
    private func hubContentMaxWidth(containerWidth: CGFloat) -> CGFloat {
        // Leave a bit more air on phone so frames/shadows aren’t flush to the viewport edge.
        let edgeSlop: CGFloat = horizontalSizeClass == .compact ? 36 : 8
        let safe = max(containerWidth - edgeSlop, 1)
        if horizontalSizeClass == .regular {
            return min(safe * 0.96, 1024)
        }
        return min(safe * 0.91, 460)
    }

    @ViewBuilder
    private var hubScrollColumn: some View {
        LazyVStack(spacing: 28) {
            Color.clear
                .frame(height: 1)
                .id("hubTop")

            if model.gameState == "lobby", model.players.isEmpty {
                if model.gameState != "deal_phase", !shouldShowHubRoleReveal {
                    hubMenuHeader
                }
                preJoinHero
            }

            if model.gameState != "deal_phase", !shouldShowHubRoleReveal,
               !(model.gameState == "lobby" && model.players.isEmpty)
            {
                hubMenuHeader
            }

            phaseStack

            if model.gameState != "deal_phase", !shouldShowHubRoleReveal {
                roomAndShareSection

                if model.gameState == "lobby" {
                    HostJoinLobbyCard(model: model, showNameSheet: $hostNameSheetPresented)
                }

                playersSection

                if model.gameState == "lobby", model.players.count >= 3 {
                    roundThemeAndNudgeSection
                    imposterSettingsSection
                }

                if model.gameState == "lobby" {
                    startButton
                }
            }

            if let err = model.lastError, model.gameState != "lobby" {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .coordinateSpace(name: "corkboardScroll")
        .backgroundPreferenceValue(CorkboardFrameKey.self) { frames in
            CorkboardStringConnectionsView(frames: frames)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var phaseStack: some View {
        if model.gameState == "deal_phase"
            || shouldShowHubRoleReveal
            || isPromptLike
            || model.gameState == "voting"
            || model.gameState == "resolution"
        {
            Group {
                if shouldShowHubRoleReveal {
                    hubRoleRevealScreen
                } else {
                    Group {
                        if model.gameState == "deal_phase" {
                            dealPhaseHoldScreen
                        } else if isPromptLike {
                            VStack(spacing: 20) {
                                activeRoundBanner
                                hostPromptControls
                            }
                        } else if model.gameState == "voting" {
                            VStack(spacing: 20) {
                                votingHostBanner
                                hostVotingControls
                            }
                        } else if model.gameState == "resolution" {
                            VStack(spacing: 20) {
                                resolutionHostBanner
                                hostResolutionControls
                            }
                        }
                    }
                    .hostPinnedPaperCard(rotation: 0.55)
                }
            }
            .trackCorkboardFrame("phase")
        }
    }

    /// Branded join-site label for the hub CTA; the `Link` still opens `BoxFortConfig.webJoinBaseURL`.
    private var joinSiteHostCTALabel: String {
        "DetectiveToast.com"
    }

    private var showdownReadyForJudgement: Bool {
        model.showdownPending && showdownCountdown <= 0
    }

    private var burntToastWinsRound: Bool {
        if model.lastImposterCaught == false { return true }
        if model.lastImposterCaught == true,
           model.showdownResolved,
           model.imposterWordGuessed == true
        {
            return true
        }
        return false
    }

    private var detectivesWinRound: Bool {
        model.lastImposterCaught == true &&
            model.showdownResolved &&
            model.imposterWordGuessed != true
    }

    private var shouldShowHubRoleReveal: Bool {
        model.gameState == "deal" && (hubRoleRevealSeenRound ?? 0) < model.roundNumber
    }

    /// Runs while `showdownPending` is true; cancelled automatically when pending ends (SwiftUI `.task`).
    private func runShowdownCountdown() async {
        showdownCountdown = 5
        isShowdownPulsing = true
        defer { isShowdownPulsing = false }
        while showdownCountdown > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled || !model.showdownPending { return }
            showdownCountdown -= 1
            isShowdownPulsing.toggle()
        }
    }

    private func syncStateAudio() {
        Task { await syncStateAudioAsync() }
    }

    private func syncStateAudioAsync() async {
        if model.showdownPending {
            await BoxFortAudio.shared.startPanicLoop()
            return
        }

        await BoxFortAudio.shared.stopPanicLoopAndResumeBackground()

        let isResolved = model.gameState == "resolution" && model.showdownResolved
        if isResolved, let caught = model.lastImposterCaught {
            let burntToastWins = (caught == false) || (model.imposterWordGuessed == true)
            if lastOutcomeAudioRound != model.roundNumber {
                lastOutcomeAudioRound = model.roundNumber
                await BoxFortAudio.shared.playOutcome(detectivesWon: !burntToastWins)
            }
            return
        }

        if model.gameState == "lobby" {
            lastOutcomeAudioRound = nil
        }
        await BoxFortAudio.shared.fadeOutOverrideIfNeeded()
        BoxFortAudio.shared.ensureBackgroundMusicIfIdle()
    }

    private var dealPhaseHoldScreen: some View {
        VStack(spacing: 14) {
            Text("Game starting")
                .font(.title2.weight(.bold))
            Text("Tell players to hide their screens. They are about to find out if they are Burnt Toast.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if model.canContinueToRoleReveal {
                Button {
                    Task { await model.continueToRoleReveal() }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(BoxFortTheme.startButtonTint(colorScheme))
            } else {
                ProgressView("Dealing roles…")
                    .padding(.top, 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    private var hubRoleRevealScreen: some View {
        let isImposter = model.hostPlayer?.role == "imposter"
        return VStack(spacing: 18) {
            if let ui = UIImage(named: isImposter ? "burnt_toast" : "detective_toast") {
                PolaroidHostFrame(topSide: 10, bottomGutter: 28) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: HubHeroImageMetrics.maxHeight(horizontalSizeClass: horizontalSizeClass))
                }
                .hostPinnedPaperCard(rotation: 0.55, showsPaperBackground: false)
            }
            VStack(spacing: 14) {
                Text(isImposter ? "You are Burnt Toast" : "You are Detective Toast")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Button {
                    hubRoleRevealSeenRound = model.roundNumber
                    BoxFortAudio.shared.playButtonPress()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(BoxFortTheme.startButtonTint(colorScheme))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 8, x: 0, y: 4)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var hubMenuHeader: some View {
        HStack {
            Text("Host")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.09))
            Spacer()
            Button {
                BoxFortAudio.shared.playButtonPress()
                showingHubMenu = true
            } label: {
                Label("Menu", systemImage: "line.3.horizontal")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.14))
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open host menu")
        }
        .padding(10)
        .hostPinnedPaperCard(rotation: -0.85)
        .trackCorkboardFrame("hubHeader")
    }

    @ViewBuilder
    private var preJoinHero: some View {
        if let ui = UIImage(named: "detective_toast_logo") {
            Image(uiImage: ui)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: horizontalSizeClass == .regular ? 132 : 108)
                .padding(.horizontal, horizontalSizeClass == .regular ? 12 : 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .trackCorkboardFrame("hero")
        }
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
        .padding(12)
        .hostPinnedPaperCard(rotation: 1.0)
        .trackCorkboardFrame("room")
    }

    private var roomCodeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Room code")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.28, green: 0.24, blue: 0.2))

            Text(model.roomCode.isEmpty ? "····" : model.roomCode)
                .font(.system(size: roomCodeFontSize, weight: .bold, design: .monospaced))
                .tracking(horizontalSizeClass == .compact ? 6 : 10)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(Color(red: 0.1, green: 0.09, blue: 0.08))
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.94, green: 0.93, blue: 0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                        )
                        .foregroundStyle(Color(red: 0.35, green: 0.3, blue: 0.26).opacity(0.55))
                )
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 320 : .infinity, alignment: .leading)
    }

    private var roomCodeFontSize: CGFloat {
        horizontalSizeClass == .regular ? 64 : 42
    }

    private var qrAndShareColumn: some View {
        VStack(spacing: 16) {
            if let url = model.inviteURL {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text("Guests join at")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Link(destination: BoxFortConfig.webJoinBaseURL) {
                            Text(verbatim: joinSiteHostCTALabel)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.45))
                                .lineLimit(1)
                                .minimumScaleFactor(0.45)
                                .multilineTextAlignment(.center)
                        }
                        .accessibilityLabel("Open Detective Toast website")
                        Text("Enter the room code from this hub when you land there.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if showInviteQRCode {
                        VStack(spacing: 10) {
                            QRCodeImage(url: url, dimension: horizontalSizeClass == .regular ? 200 : 180)
                            Text("Scan to join (room only — each phone gets its own slice)")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Button {
                            BoxFortAudio.shared.playButtonPress()
                            showInviteQRCode = false
                        } label: {
                            Label("Hide QR code", systemImage: "chevron.up")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            BoxFortAudio.shared.playButtonPress()
                            showInviteQRCode = true
                        } label: {
                            Label("Show QR code", systemImage: "qrcode")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.93, green: 0.92, blue: 0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )

                Button {
                    BoxFortAudio.shared.playButtonPress()
                    if let url = model.inviteURL {
                        UIPasteboard.general.string = url.absoluteString
                        showCopiedLinkMessage = true
                    }
                } label: {
                    Label("Copy invite link", systemImage: "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(BoxFortTheme.shareButtonTint(colorScheme))

                if let resume = model.hostPlayerResumeURL {
                    Button {
                        BoxFortAudio.shared.playButtonPress()
                        UIPasteboard.general.string = resume.absoluteString
                        showCopiedLinkMessage = true
                    } label: {
                        Label("Copy my phone link (same player as this hub)", systemImage: "iphone")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    Text(
                        "Only for you on a second device. Other players must use the QR or room-only link — otherwise they share your player and your vote."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var activeRoundBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Round \(model.roundNumber)", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            Text(
                "Phones keep roles private. Press and hold below to see what applies on this hub: secret word and picture, or Burnt Toast status (and an optional pass-1 word when the game gives one)."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let prompt = model.currentPrompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BoxFortTheme.promptBubble(colorScheme))
                    )
            }
            HostHoldToRevealCard(
                isBurntHost: model.hostPlayer?.role == "imposter",
                burntNudgeOnlyWhileSpeaking: model.hostPlayer?.role == "imposter"
                    && model.hostPlayerId == model.currentSpeakerId,
                clueRound: model.clueRound,
                burntNudgeWords: model.hostPlayer?.imposterNudgeWords,
                urlString: model.roundImageUrl,
                crewWord: model.crewWord,
                isRevealing: $hostRevealingRoundImage,
                colorScheme: colorScheme
            )
            .onChange(of: model.roundNumber) { _, _ in
                hostRevealingRoundImage = false
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BoxFortTheme.dealBannerFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(BoxFortTheme.dealBannerStroke(colorScheme))
        )
    }

    private var votingHostBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            fullWidthCharacterImage(name: "chief_loaf", fallbackSystemName: "crown.fill")
            Label("Vote", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("Tell Chief Loaf who Burnt Toast is. Chief Loaf judges by top votes (ties count).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BoxFortTheme.dealBannerFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(BoxFortTheme.dealBannerStroke(colorScheme))
        )
    }

    private var resolutionHostBanner: some View {
        let imps = model.players.filter { $0.role == "imposter" }
        return VStack(alignment: .leading, spacing: 8) {
            Label("The loaf's verdict", systemImage: "sparkles")
                .font(.headline)
            if detectivesWinRound || burntToastWinsRound {
                fullWidthCharacterImage(
                    name: detectivesWinRound ? "detectives_won" : "burnt_toast_won",
                    fallbackSystemName: detectivesWinRound ? "checkmark.seal.fill" : "flame.fill"
                )
            }
            if imps.count == 1, let imp = imps.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chief Loaf names Burnt Toast")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(imp.displayName)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.18))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.55), lineWidth: 2)
                        )
                }
            } else if imps.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Chief Loaf names the Burnt Toasts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(imps) { p in
                        Text(p.displayName)
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.18))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.orange.opacity(0.45), lineWidth: 2)
                            )
                    }
                }
            }
            if let host = model.hostPlayer {
                if host.role == "imposter" {
                    if model.showdownPending {
                        Text("Chief Loaf grants one final chance: Burnt Toast may guess the secret word.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if model.imposterWordGuessed == true {
                        Text("Burnt Toast was caught, but guessed the secret word correctly — Burnt Toast wins this round.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Burnt Toast was caught and missed the final guess — Detective Toasts win this round.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                } else if let ok = host.lastVoteCorrect {
                    if model.imposterWordGuessed == true, ok {
                        Text("You found Burnt Toast, but they guessed the word — Burnt Toast wins this round.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text(ok ? "You found Burnt Toast — detective instincts." : "Your vote missed Burnt Toast.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ok ? .green : .orange)
                    }
                } else {
                    Text("Chief Loaf recorded your vote; verdict shown above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Scoring: if Burnt Toast is caught and misses the final guess, Detective Toasts gain +100 each. If Burnt Toast escapes OR guesses correctly, Burnt Toasts gain +100 each.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BoxFortTheme.dealBannerFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(BoxFortTheme.dealBannerStroke(colorScheme))
        )
    }

    private var hostPromptControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clue passes completed: \(model.clueRound).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Speaking order")
                .font(.subheadline.weight(.semibold))
            if model.turnOrder.isEmpty {
                Text("Order appears after the round starts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.turnOrder.enumerated()), id: \.element) { idx, pid in
                    let name = model.players.first(where: { $0.id == pid })?.displayName ?? "Player"
                    HStack {
                        Text("\(idx + 1).")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                        Text(name)
                            .font(.body.weight(model.currentSpeakerId == pid ? .bold : .regular))
                        if model.currentSpeakerId == pid {
                            Text("speaks now")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button {
                            Task { await model.swapTurnOrder(at: idx, with: idx - 1) }
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .disabled(idx == 0 || model.isBusyPhase)
                        Button {
                            Task { await model.swapTurnOrder(at: idx, with: idx + 1) }
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(idx >= model.turnOrder.count - 1 || model.isBusyPhase)
                    }
                    .padding(.vertical, 6)
                }
            }
            if let speaker = model.currentSpeakerName {
                Text("Now: \(speaker)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let hid = model.hostPlayerId, model.currentSpeakerId == hid {
                Text("Your turn: give your clue on the hub now.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await model.nextSpeaker() }
                } label: {
                    Text(
                        model.canStartNextCluePass
                            ? "Finish pass → next clue round"
                            : "Next speaker"
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BoxFortTheme.startButtonTint(colorScheme))
                .disabled(model.turnOrder.isEmpty || model.isBusyPhase)
                Button {
                    Task { await model.startVoting() }
                } label: {
                    Text("Start voting")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.turnOrder.isEmpty || model.isBusyPhase)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BoxFortTheme.cardFillSecondary(colorScheme))
        )
    }

    private var hostVotingControls: some View {
        VStack(spacing: 12) {
            if model.voteTallyBySuspect.values.contains(where: { $0 > 0 }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live votes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(
                        model.players.filter { (model.voteTallyBySuspect[$0.id] ?? 0) > 0 }
                    ) { p in
                        let n = model.voteTallyBySuspect[p.id] ?? 0
                        HStack {
                            Text(p.displayName)
                            Spacer()
                            Text("\(n) vote\(n == 1 ? "" : "s")")
                                .font(.body.monospacedDigit().weight(.semibold))
                        }
                        .font(.subheadline)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BoxFortTheme.cardFill(colorScheme, prominent: true))
                )
            }
            if let hub = model.hostPlayer {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your hub vote")
                        .font(.subheadline.weight(.semibold))
                    Text("Tell the loaf who you think the Burnt Toast is.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.players.filter { $0.id != hub.id }) { p in
                        Button {
                            Task { await model.castHubVote(for: p.id) }
                        } label: {
                            HStack {
                                Text(p.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if hub.voteFor == p.id {
                                    Label("your vote", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill((hub.voteFor == p.id) ? BoxFortTheme.capsuleBadge(colorScheme) : BoxFortTheme.cardFill(colorScheme))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusyPhase)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await model.resolveRound() }
            } label: {
                if model.isBusyPhase {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Ask the loaf for verdict")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(BoxFortTheme.shareButtonTint(colorScheme))
            .disabled(model.isBusyPhase)
        }
    }

    private var hostResolutionControls: some View {
        VStack(spacing: 12) {
            if model.showdownPending {
                VStack(spacing: 12) {
                    Text("Final Guess Showdown")
                        .font(.headline)
                        .foregroundStyle(.white)
                    characterImage(name: "detective_toast_panic", fallbackSystemName: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity, maxHeight: HubHeroImageMetrics.maxHeight(horizontalSizeClass: horizontalSizeClass), alignment: .center)
                    Text(showdownCountdown > 0
                        ? "Burnt Toast has \(showdownCountdown) seconds to shout the secret word."
                        : "Did Burnt Toast guess the secret word correctly?")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                    if showdownCountdown > 0 {
                        Text("\(showdownCountdown)")
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.top, 6)
                    } else {
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await BoxFortAudio.shared.stopPanicLoopAndResumeBackground()
                                    await model.resolveShowdown(imposterGuessedWordCorrect: true)
                                }
                            } label: {
                                Text("Yes, guessed correctly")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.black.opacity(0.35))

                            Button {
                                Task {
                                    await BoxFortAudio.shared.stopPanicLoopAndResumeBackground()
                                    await model.resolveShowdown(imposterGuessedWordCorrect: false)
                                }
                            } label: {
                                Text("No, missed it")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.black.opacity(0.35))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.85))
                )
                .scaleEffect(isShowdownPulsing ? 1.02 : 0.98)
                .animation(.easeInOut(duration: 0.35), value: isShowdownPulsing)
                .id("hubShowdown")
            }

            ForEach(model.players.sorted(by: { a, b in
                if a.score == b.score { return a.displayName < b.displayName }
                return a.score > b.score
            })) { p in
                HStack {
                    Text(p.displayName)
                    Spacer()
                    Text("\(p.score) pts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(BoxFortTheme.cardFill(colorScheme))
                )
            }
            Button {
                Task { await model.nextRoundLobby() }
            } label: {
                if model.isBusyPhase {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Next round")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(BoxFortTheme.startButtonTint(colorScheme))
            .disabled(model.isBusyPhase || model.showdownPending)
        }
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Players")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.09))
                Spacer()
                Text("\(model.players.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.3, blue: 0.26))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.07)))
            }

            if model.players.isEmpty {
                Text("Waiting for slices to join…")
                    .font(.body)
                    .foregroundStyle(Color(red: 0.4, green: 0.36, blue: 0.32))
            } else {
                ForEach(model.players) { p in
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.2))
                        Text(p.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color(red: 0.1, green: 0.09, blue: 0.08))
                        if model.hostPlayerId == p.id {
                            Text("hub")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(red: 0.4, green: 0.36, blue: 0.32))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.94, green: 0.93, blue: 0.91))
                    )
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hostPinnedPaperCard(rotation: -0.75)
        .trackCorkboardFrame("players")
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
                    .foregroundStyle(Color(red: 0.4, green: 0.36, blue: 0.32))
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
            .tint(BoxFortTheme.startButtonTint(colorScheme))
            .disabled(!model.canStartGame)

            Text("Need at least 3 players. The AI bakes a prompt and secret word; toast portraits come from the web library, and you set how many Burnt Toast slices.")
                .font(.caption)
                .foregroundStyle(Color(red: 0.4, green: 0.36, blue: 0.32))
                .multilineTextAlignment(.center)
        }
        .padding(10)
        .hostPinnedPaperCard(rotation: 0.9)
        .trackCorkboardFrame("start")
    }

    private struct RoundThemeCard: Identifiable {
        let id: String
        let title: String
        let emoji: String
    }

    private static let roundThemeCards: [RoundThemeCard] = [
        RoundThemeCard(id: "food", title: "Food & snacks", emoji: "🍎"),
        RoundThemeCard(id: "animals", title: "Animals", emoji: "🐻"),
        RoundThemeCard(id: "vehicles", title: "Vehicles", emoji: "🚌"),
        RoundThemeCard(id: "nature", title: "Nature & weather", emoji: "🌈"),
        RoundThemeCard(id: "toys", title: "Toys & play", emoji: "🧸"),
        RoundThemeCard(id: "movies", title: "Movies", emoji: "🎬"),
    ]

    private var roundThemeAndNudgeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This round’s theme")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.09))
            Text(
                "Picks the kind of secret word and picture everyone chases. Words are kid-friendly; icons use simple search terms so the picture reads clearly on phones."
            )
            .font(.caption)
            .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Self.roundThemeCards) { card in
                    let selected = model.roundTheme == card.id
                    CaseFileThemePickCard(
                        title: card.title,
                        emoji: card.emoji,
                        selected: selected
                    ) {
                        Task { await model.setRoundTheme(card.id) }
                    }
                    .disabled(model.isBusyPhase)
                }
            }

            Text("Burnt Toast: early decoy words")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.09))
                .padding(.top, 4)
            Picker(
                "Early slots",
                selection: Binding(
                    get: { model.nudgeEarlySlots },
                    set: { v in Task { await model.setNudgeEarlySlots(v) } }
                )
            ) {
                Text("1 — first speaker").tag(1)
                Text("2 — first two speakers").tag(2)
            }
            .pickerStyle(.segmented)
            .disabled(model.isBusyPhase)
            Text(
                "Speaking order is fully random, so Burnt Toast might go first. On the first clue pass only, anyone who is Burnt Toast and speaks in one of the first slots gets one optional decoy word. Default 1 covers only the very first speaker; use 2 if you want both early seats covered (helpful with two Burnt slices or bigger groups)."
            )
            .font(.caption)
            .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hostPinnedPaperCard(rotation: -0.55)
        .trackCorkboardFrame("themes")
    }

    private var imposterSettingsSection: some View {
        let cap = HostViewModel.maxImpostersAllowed(forPlayerCount: model.players.count)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Loaf settings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.09))
            if cap <= 1 {
                Text("With 3–6 players there is one Burnt Toast. Add a 7th slice to allow two in the same round.")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
            } else {
                Stepper(value: Binding(
                    get: { model.imposterCount },
                    set: { newVal in Task { await model.setImposterCount(newVal) } }
                ), in: 1 ... cap) {
                    Text("Burnt Toast slices: \(model.imposterCount)")
                        .font(.body)
                }
                .disabled(model.isBusyPhase)
                Text("Golden slices share one secret word and the picture; Burnt Toast gets neither.")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hostPinnedPaperCard(rotation: 0.65)
        .trackCorkboardFrame("loaf")
    }

    @ViewBuilder
    private func characterImage(name: String, fallbackSystemName: String) -> some View {
        let maxH = HubHeroImageMetrics.maxHeight(horizontalSizeClass: horizontalSizeClass)
        if let ui = UIImage(named: name) {
            PolaroidHostFrame(topSide: 8, bottomGutter: 24) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: maxH)
            }
        } else {
            Image(systemName: fallbackSystemName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(
                    Circle().fill(BoxFortTheme.cardFill(colorScheme))
                )
        }
    }

    @ViewBuilder
    private func fullWidthCharacterImage(name: String, fallbackSystemName: String) -> some View {
        let maxH = HubHeroImageMetrics.maxHeight(horizontalSizeClass: horizontalSizeClass)
        if let ui = UIImage(named: name) {
            PolaroidHostFrame(topSide: 10, bottomGutter: 30) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: maxH)
            }
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(BoxFortTheme.cardFill(colorScheme))
                )
        }
    }
}

// MARK: - Host join (sheet: text field is not inside the polled hub ScrollView — avoids keyboard lag)

private struct HostJoinLobbyCard: View {
    @Bindable var model: HostViewModel
    @Binding var showNameSheet: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join the game too?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.09))
            Text(
                "Add your name so you’re a real slice in the game. You can still use your phone, but the hub can now cast your vote here too."
            )
            .font(.caption)
            .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
            if model.hostPlayerId == nil {
                Button {
                    BoxFortAudio.shared.playButtonPress()
                    showNameSheet = true
                } label: {
                    Text("Enter your name…")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(BoxFortTheme.shareButtonTint(colorScheme))
                .disabled(!model.canAddHostAsPlayer || model.isBusyPhase)
            }
            if model.hostPlayerId != nil {
                Label(
                    "You’re in the loaf — this hub can show your turn and cast your vote. The big QR is room-only for guests. Use “Copy my phone link” only on your own second device so you don’t merge someone else into your player.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(red: 0.38, green: 0.33, blue: 0.28))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hostPinnedPaperCard(rotation: -0.45)
        .trackCorkboardFrame("hostJoin")
    }
}

/// Same chrome for every hub role: press-and-hold reveals detective secrets, Burnt Toast identity, or an optional pass-1 decoy — so the block never leaks who is Burnt by being missing.
private struct HostHoldToRevealCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var isBurntHost: Bool
    /// Pass-1 decoy is only shown while Burnt Toast is the current speaker (so it disappears after their turn).
    var burntNudgeOnlyWhileSpeaking: Bool
    var clueRound: Int
    var burntNudgeWords: [String]?
    var urlString: String?
    var crewWord: String?
    @Binding var isRevealing: Bool
    var colorScheme: ColorScheme

    private var hasURL: Bool {
        guard let s = urlString, !s.isEmpty else { return false }
        return true
    }

    private var trimmedWord: String? {
        guard let w = crewWord?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty else { return nil }
        return w
    }

    private var goldenHasContent: Bool {
        trimmedWord != nil || hasURL
    }

    /// Pass 1 only: optional server nudge for Burnt Toast in an early speaking slot, only while they are up.
    private var burntPassOneNudge: String? {
        guard isBurntHost,
            burntNudgeOnlyWhileSpeaking,
            clueRound == 0,
            let w = burntNudgeWords?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            !w.isEmpty
        else { return nil }
        return w
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(BoxFortTheme.cardFill(colorScheme).opacity(0.45))
            if isRevealing {
                revealedLayer
                    .padding(16)
            } else {
                collapsedLayer
                    .padding(16)
            }
        }
        .frame(minHeight: 160)
        .frame(maxHeight: isRevealing ? min(620, HubHeroImageMetrics.maxHeight(horizontalSizeClass: horizontalSizeClass) + 200) : 260)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isRevealing = true
                }
                .onEnded { _ in
                    isRevealing = false
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hidden until you press and hold")
    }

    @ViewBuilder
    private var collapsedLayer: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Hold to reveal")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Text("Keep holding to read. Release to hide again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var revealedLayer: some View {
        if isBurntHost {
            if let nudge = burntPassOneNudge {
                VStack(spacing: 12) {
                    Text("You are Burnt Toast")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Optional word (pass 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(nudge)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    if let ui = UIImage(named: "burnt_toast") {
                        PolaroidHostFrame(topSide: 8, bottomGutter: 22) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: HubHeroImageMetrics.maxHeight(horizontalSizeClass: horizontalSizeClass) * 0.42)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    if let ui = UIImage(named: "burnt_toast") {
                        PolaroidHostFrame(topSide: 8, bottomGutter: 26) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: HubHeroImageMetrics.maxHeight(horizontalSizeClass: horizontalSizeClass) * 0.88)
                        }
                    }
                    Text("You are the Burnt Toast")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        } else if goldenHasContent {
            VStack(spacing: 14) {
                if let w = trimmedWord {
                    VStack(spacing: 6) {
                        Text("Secret word")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(w)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                if hasURL {
                    RoundImageView(urlString: urlString)
                        .frame(maxWidth: HubHeroImageMetrics.roundObjectMaxSide(horizontalSizeClass: horizontalSizeClass))
                } else if trimmedWord != nil {
                    Text("No picture this round — word only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("No crew word or picture this round (check Edge Function logs).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Renders a remote image URL for the round object (e.g. Freepik icon).
private struct RoundImageView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var urlString: String?

    private var maxImgSide: CGFloat {
        HubHeroImageMetrics.roundObjectMaxSide(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        PolaroidHostFrame(topSide: 8, bottomGutter: 26) {
            Group {
                if let s = urlString, !s.isEmpty {
                    if s.lowercased().hasPrefix("data:"), let ui = Self.uiImage(fromDataURL: s) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                    } else if let u = URL(string: s),
                        u.scheme == "http" || u.scheme == "https"
                    {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 120)
                            case let .success(img):
                                img.resizable().scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxImgSide)
        }
    }

    private static func uiImage(fromDataURL s: String) -> UIImage? {
        guard let r = s.range(of: "base64,") else { return nil }
        let b64 = String(s[r.upperBound...])
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }
}

#Preview {
    @Previewable @State var showName = false
    LobbyView(model: HostViewModel(), hostNameSheetPresented: $showName)
}
