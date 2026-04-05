import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BoxFort")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(3)

                    Text("Dr. Toast's Mix-Up")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("A silly word game for families — you talk out loud; phones hold the secrets.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ruleRow(
                        icon: "fork.knife",
                        title: "Chefs (Crew)",
                        detail: "You all get the right mystery ingredient. Describe the prompt using that word when it's your turn."
                    )
                    ruleRow(
                        icon: "takeoutbag.and.cup.and.straw.fill",
                        title: "Sneaky Snacker (Imposter)",
                        detail: "You get a different ingredient that almost fits. Blend in without giving yourself away."
                    )
                    ruleRow(
                        icon: "ipad.and.iphone",
                        title: "Big screen + phones",
                        detail: "The iPad shows the room code and the story. Phones only show your secret word and later, votes."
                    )
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.brown.opacity(0.2), lineWidth: 1)
                )

                Button(action: onContinue) {
                    Text("Host a game")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.55, green: 0.35, blue: 0.12))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func ruleRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color(red: 0.5, green: 0.35, blue: 0.15))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
