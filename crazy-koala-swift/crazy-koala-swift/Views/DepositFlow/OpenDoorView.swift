// Views/DepositFlow/OpenDoorView.swift
// Door open/close instruction screen (dev-plan §6.4)

import SwiftUI

struct OpenDoorView: View {
    @EnvironmentObject var appState: AppState

    @State private var doorOpened = false

    private var isConnected: Bool {
        appState.tcpClient.connectionState == .connected
    }

    private var isDeposit: Bool {
        appState.mode == .deposit
    }

    var body: some View {
        VStack(spacing: 0) {
            YellowBar(title: isDeposit ? "Store Your Item" : "Retrieve Your Item")

            Spacer()

            // Door image
            BundleImage(name: doorOpened ? "door_open" : "door_close", maxWidth: 250, maxHeight: 250)

            Text(isDeposit ? "Open the door to store the item." : "Open the door to retrieve the item.")
                .font(.poppins(.medium, size: 20))
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            // Connection warning
            if !isConnected {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Cannot connect to the lock")
                        .font(.poppins(.regular, size: 14))
                        .foregroundColor(.orange)
                }
                .padding(.top, 8)
            }

            Spacer()

            // Buttons
            HStack(spacing: 30) {
                // Cancel button — always available
                Button {
                    appState.sessionLog.log(.tapBack, details: ["from": "OpenDoorView"])
                    appState.returnToModeSelection()
                } label: {
                    Text("Cancel")
                        .font(.poppins(.medium, size: 18))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                }

                if !doorOpened {
                    // Open Door button
                    RoundedButton(title: "Open Door") {
                        openDoor()
                    }
                    .opacity(isConnected ? 1.0 : 0.4)
                    .disabled(!isConnected)
                } else {
                    // Done button
                    RoundedButton(title: "Done") {
                        handleDone()
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .navigationBarHidden(true)
        .onAppear {
            appState.sessionLog.log(.viewAppear, details: ["view": "OpenDoorView"])
        }
    }

    // MARK: - Open Door (§6.4)

    private func openDoor() {
        appState.tcpClient.send("2")
        appState.sessionLog.log(.doorUnlock)
        appState.sessionLog.log(.esp32Tx, details: ["code": "2", "meaning": "unlock"])
        appState.audioService.playBundled(name: "open_door")
        doorOpened = true
    }

    // MARK: - Done (§6.4)

    private func handleDone() {
        appState.tcpClient.send("1")
        appState.sessionLog.log(.doorLock)
        appState.sessionLog.log(.esp32Tx, details: ["code": "1", "meaning": "lock"])
        appState.sessionLog.log(.tapDone, details: ["from": "OpenDoorView", "mode": appState.mode?.rawValue ?? ""])

        if isDeposit {
            // Return to mode-selection (session stays active)
            appState.returnToModeSelection()
        } else {
            // Take mode: navigate to prompt then PhotoAudioView for retrieval photo/audio
            appState.navigate(to: .takePrompt)
        }
    }
}
