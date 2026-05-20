// Views/HomeView.swift
// Landing screen: welcome state + mode-selection state (dev-plan §6.1)

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    @State private var showDebug = false
    @State private var showLockWarning = false

    var body: some View {
        NavigationStack(path: $appState.navigationPath) {
            Group {
                if appState.isSessionActive {
                    modeSelectionView
                } else {
                    welcomeView
                }
            }
            .navigationDestination(for: NavDestination.self) { destination in
                switch destination {
                case .inputName:
                    InputNameView()
                        .environmentObject(appState)
                case .depositPrompt:
                    PromptView(
                        message: "Give your item a personal touch!\nAdd a photo or record a quick audio message.",
                        destination: .photoAudio
                    )
                    .environmentObject(appState)
                case .photoAudio:
                    PhotoAudioView(cameraService: appState.cameraService, audioService: appState.audioService)
                        .environmentObject(appState)
                case .openDoor:
                    OpenDoorView()
                        .environmentObject(appState)
                case .selectItem:
                    SelectItemView()
                        .environmentObject(appState)
                case .viewDeposit:
                    ViewDepositView(audioService: appState.audioService)
                        .environmentObject(appState)
                case .takePrompt:
                    PromptView(
                        message: "A photo or voice note for the item you're taking?\nIt'll be saved to the Happy Memories!",
                        destination: .photoAudio
                    )
                    .environmentObject(appState)
                case .gallery:
                    GalleryView()
                        .environmentObject(appState)
                case .detail:
                    DetailView(audioService: appState.audioService)
                        .environmentObject(appState)
                }
            }
        }
        .onAppear {
            setupESP32Handler()
        }
        .sheet(isPresented: $showDebug) {
            DebugView(tcpClient: appState.tcpClient, sessionLogService: appState.sessionLog)
        }
        .alert("Door Lock Warning", isPresented: $showLockWarning) {
            Button("OK") {}
        } message: {
            Text("Door lock could not be confirmed. Please verify manually.")
        }
    }

    // MARK: - Welcome Screen (§6.1)

    private var welcomeView: some View {
        VStack {
            Spacer()

            HStack(spacing: 40) {
                // Left: door image
                BundleImage(name: "door_close", maxHeight: 500)

                // Right: text + button, left-aligned
                VStack(alignment: .leading, spacing: 20) {
                    (Text("Connect to Our \nCommunity \nTogether\n")
                        .font(.poppins(.bold, size: 48))
                    + Text("for Better Future")
                        .font(.poppins(.regular, size: 42)))
                        .multilineTextAlignment(.leading)

                    RoundedButton(title: "Press Koala's Nose to Start") {
                        appState.startSession(trigger: .tapStart)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Debug button: ant.fill at bottom-left (§6.1)
            HStack {
                Button {
                    showDebug = true
                } label: {
                    Image(systemName: "ant.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .navigationBarHidden(true)
    }

    // MARK: - Mode Selection (§6.1)

    private var modeSelectionView: some View {
        VStack(spacing: 0) {
            YellowBar(title: "Choose an Action")

            Spacer()

            HStack(spacing: 40) {
                modeButton(title: "Deposit", imageName: "deposit", mode: .deposit) {
                    appState.sessionLog.log(.selectMode, details: ["mode": "deposit"])
                    appState.navigate(to: .inputName, mode: .deposit)
                }

                modeButton(title: "Take", imageName: "take", mode: .take) {
                    appState.sessionLog.log(.selectMode, details: ["mode": "take"])
                    appState.navigate(to: .selectItem, mode: .take)
                }

                modeButton(title: "Happy Memories", imageName: "happy", mode: .memories) {
                    appState.sessionLog.log(.selectMode, details: ["mode": "memories"])
                    appState.navigate(to: .gallery, mode: .memories)
                }
            }

            Spacer()

            // End Session button (§6.1)
            Button {
                endSession()
            } label: {
                Text("End Session")
                    .font(.poppins(.medium, size: 18))
                    .foregroundColor(.red)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red, lineWidth: 2)
                    )
            }
            .padding(.bottom, 30)
        }
        .navigationBarHidden(true)
    }

    // MARK: - Mode Button

    private func modeButton(title: String, imageName: String, mode: Mode, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                BundleImage(name: imageName, maxWidth: 200, maxHeight: 200)

                Text(title)
                    .font(.poppins(.bold, size: 32))
                    .foregroundColor(.primary)
            }
            .padding(20)
        }
    }

    // MARK: - End Session (§6.1)

    private func endSession() {
        // Send lock with ACK verification (§5.4)
        appState.tcpClient.sendLockAndVerify(timeout: 2, retries: 1) { success in
            DispatchQueue.main.async {
                if !success {
                    showLockWarning = true
                }
                // Play goodbye audio and return to welcome
                appState.audioService.playBundled(name: "goodbye")
                appState.endSession()
            }
        }
    }

    // MARK: - ESP32 '3' Handler (§6.1)

    private func setupESP32Handler() {
        appState.tcpClient.onReceive = { [weak appState] char in
            guard let appState else { return }
            // '3' = Enter Home View (BOOT button pressed)
            // Only advance if no session is active (§5.5)
            if char == "3" && !appState.isSessionActive {
                appState.startSession(trigger: .esp32Button)
            }
        }
    }
}
