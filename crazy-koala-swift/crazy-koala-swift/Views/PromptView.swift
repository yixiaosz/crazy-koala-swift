// Views/PromptView.swift
// Transition screen shown before PhotoAudioView in deposit and take flows

import SwiftUI

struct PromptView: View {
    @EnvironmentObject var appState: AppState

    let message: String
    let destination: NavDestination

    var body: some View {
        VStack(spacing: 0) {
            YellowTitleBar(title: appState.mode == .deposit ? "Before You Go" : "One More Thing") {
                appState.sessionLog.log(.tapBack, details: ["from": "PromptView"])
                appState.goBack()
            }

            Spacer()

            Text(message)
                .font(.poppins(.medium, size: 22))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)

            Spacer()

            RoundedButton(title: "Continue") {
                appState.sessionLog.log(.tapNext, details: ["from": "PromptView"])
                appState.navigate(to: destination)
            }
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .onAppear {
            appState.sessionLog.log(.viewAppear, details: ["view": "PromptView"])
        }
    }
}
