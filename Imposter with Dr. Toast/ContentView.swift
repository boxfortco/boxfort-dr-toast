//
//  ContentView.swift
//  Imposter with Dr. Toast
//
//  BoxFort host — onboarding + responsive lobby.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("boxfortOnboardingComplete") private var onboardingComplete = false
    @State private var model = HostViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.93, blue: 0.88),
                    Color(red: 0.90, green: 0.85, blue: 0.78),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if onboardingComplete {
                LobbyView(model: model)
            } else {
                OnboardingView {
                    withAnimation(.easeInOut) {
                        onboardingComplete = true
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
