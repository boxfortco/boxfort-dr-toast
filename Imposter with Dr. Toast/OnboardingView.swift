import SwiftUI

private enum OnboardingPalette {
    static let bg = Color.black
    static let title = Color.white
    static let body = Color.white.opacity(0.78)
    static let muted = Color.white.opacity(0.55)
    static let card = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.22)
}

/// Noir onboarding: black canvas, white type. Avoids `ScrollView` inside page `TabView` (can crash when swiping).
struct OnboardingView: View {
    let onContinue: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            OnboardingPalette.bg.ignoresSafeArea()

            TabView(selection: $page) {
                chasePage.tag(0)
                roomAndQRPage.tag(1)
                rolesPage.tag(2)
                cluesPage.tag(3)
                trustPage.tag(4)
                finalePage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: page == 5 ? .never : .always))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var chasePage: some View {
        OnboardingCard {
            ZStack(alignment: .bottomTrailing) {
                assetImage("detective_toast_logo")
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)

                assetImage("burnt_toast")
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.6), lineWidth: 2)
                    )
                    .offset(x: -8, y: 8)
            }
            .frame(maxHeight: 300)
        } title: {
            Text("The chase is on")
        } subtitle: {
            Text("Detective Toast is hot on the trail of the **elusive Burnt Toast** — slippery, smoky, and nowhere near the real answer.")
        }
    }

    private var roomAndQRPage: some View {
        OnboardingCard {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(OnboardingPalette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(OnboardingPalette.cardStroke, lineWidth: 1)
                    )
                    .overlay {
                        HStack(alignment: .center, spacing: 4) {
                            onboardingQRCodeColumn()
                            phonePortraitColumn(imageName: "detective_toast")
                            phonePortraitColumn(imageName: "burnt_toast")
                            phonePortraitColumn(imageName: "detective_toast")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                    }
                    .frame(maxHeight: 200)

                Text("Scan · join · play")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingPalette.muted)
                    .tracking(1.2)
            }
            .frame(maxWidth: .infinity)
        } title: {
            Text("One host, a room full of phones")
        } subtitle: {
            Text("Start a game on **this** device. Everyone else grabs their phone and **scans the QR** — no sign-ups, just crumbs and chaos.")
        }
    }

    private var rolesPage: some View {
        OnboardingCard {
            HStack(spacing: 12) {
                roleTile(
                    imageName: "detective_toast",
                    label: "Detective Toast",
                    tint: Color.blue.opacity(0.22)
                )
                roleTile(
                    imageName: "burnt_toast",
                    label: "Burnt Toast",
                    tint: Color.orange.opacity(0.28)
                )
            }
            .frame(maxHeight: 280)
        } title: {
            Text("Which slice are you?")
        } subtitle: {
            Text("Detectives get the picture and the **secret word**. Burnt Toast? **No intel** — only nerves of stale bread.")
        }
    }

    private var cluesPage: some View {
        OnboardingCard {
            assetImage("detectives_won")
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .bottom) {
                    Text("“…**maybe** something **crunchy**?”")
                        .font(.caption.italic())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        } title: {
            Text("One clue at a time")
        } subtitle: {
            Text("Take turns dropping a **word or phrase** that fits the secret. Burnt Toast is **flying blind** — bluff, stall, or pray nobody notices.")
        }
    }

    private var trustPage: some View {
        OnboardingCard {
            assetImage("detective_toast_panic")
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        } title: {
            Text("Truth… or toaster smoke?")
        } subtitle: {
            Text("**Who’s on the level** — and who’s buttering you up? Watch, listen, then **vote** when the table’s ready.")
        }
    }

    private var finalePage: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 36)

            assetImage("detective_toast")
                .frame(maxWidth: 200, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)

            VStack(spacing: 12) {
                Text("It’s time for")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(OnboardingPalette.muted)
                Text("Detective Toast:\nHunt for the Burnt Toast")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingPalette.title)
            }
            .padding(.horizontal, 8)

            Text("Grab your crew, dim the lights, and don’t trust the crust.")
                .font(.body)
                .foregroundStyle(OnboardingPalette.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer(minLength: 24)

            Button {
                BoxFortAudio.shared.playButtonPress()
                onContinue()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pieces

    /// Column 1: static QR stand-in (avoids Core Image QR in `TabView` paging).
    private func onboardingQRCodeColumn() -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white)
            .frame(width: OnboardingLayout.phonePortrait.width, height: OnboardingLayout.phonePortrait.height)
            .overlay {
                Image(systemName: "qrcode")
                    .font(.system(size: 32))
                    .foregroundStyle(.black.opacity(0.78))
            }
            .accessibilityLabel("Example QR code to join a room")
            .frame(maxWidth: .infinity)
    }

    /// Columns 2–4: same “phone” silhouette; detective repeated in first and last column.
    private func phonePortraitColumn(imageName: String) -> some View {
        Group {
            if let ui = UIImage(named: imageName) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(OnboardingPalette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OnboardingPalette.card)
            }
        }
        .frame(width: OnboardingLayout.phonePortrait.width, height: OnboardingLayout.phonePortrait.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }

    private enum OnboardingLayout {
        /// Narrow portrait frame so four columns fit on phone widths (~9:16).
        static let phonePortrait = CGSize(width: 54, height: 96)
    }

    private func roleTile(imageName: String, label: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            assetImage(imageName)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnboardingPalette.title)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(OnboardingPalette.cardStroke.opacity(0.6), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func assetImage(_ name: String) -> some View {
        if let ui = UIImage(named: name) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(OnboardingPalette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Card shell (no ScrollView — avoids TabView swipe crashes)

private struct OnboardingCard<Title: View, Subtitle: View, Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let title: () -> Title
    @ViewBuilder let subtitle: () -> Subtitle

    init(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder title: @escaping () -> Title,
        @ViewBuilder subtitle: @escaping () -> Subtitle
    ) {
        self.content = content
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            VStack(spacing: 22) {
                content()
                    .padding(.top, 8)

                title()
                    .font(.title2.weight(.bold))
                    .foregroundStyle(OnboardingPalette.title)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                subtitle()
                    .font(.body)
                    .foregroundStyle(OnboardingPalette.body)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 560)

            Spacer(minLength: 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
