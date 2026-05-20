// Views/TakeFlow/ViewDepositView.swift
// Deposit detail view before retrieval (dev-plan §6.6)

import SwiftUI

struct ViewDepositView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioService: AudioService

    private var item: Item? { appState.currentItem }

    var body: some View {
        VStack(spacing: 0) {
            YellowTitleBar(title: item?.name ?? "Item Details") {
                appState.sessionLog.log(.tapBack, details: ["from": "ViewDepositView"])
                appState.goBack()
            }

            if let item {
                Spacer()

                VStack(spacing: 20) {
                    // Deposit photo
                    if let photoPath = item.depositPhotoPath {
                        let absPath = DatabaseService.resolveAbsolutePath(photoPath)
                        if let uiImage = UIImage(contentsOfFile: absPath) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 350, maxHeight: 350)
                                .cornerRadius(12)
                        }
                    }

                    // Item name
                    Text(item.name)
                        .font(.poppins(.bold, size: 24))

                    // Deposit timestamp
                    if let date = item.depositCreatedAt {
                        Text("Deposited: \(Item.displayDateFormatter.string(from: date))")
                            .font(.poppins(.regular, size: 14))
                            .foregroundColor(.secondary)
                    }

                    // Play deposit audio
                    if let audioPath = item.depositAudioPath {
                        let absPath = DatabaseService.resolveAbsolutePath(audioPath)
                        Button {
                            if audioService.isPlaying {
                                audioService.stopPlayback()
                            } else {
                                let url = URL(fileURLWithPath: absPath)
                                audioService.play(url: url)
                                appState.sessionLog.log(.playAudio, details: ["file": url.lastPathComponent])
                            }
                        } label: {
                            HStack {
                                BundleImage(name: "Trumpet", maxWidth: 24, maxHeight: 24)
                                Text(audioService.isPlaying ? "Stop Audio" : "Play Deposit Audio")
                                    .font(.poppins(.medium, size: 16))
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()

                // Take button
                RoundedButton(title: "Take This Item") {
                    appState.sessionLog.log(.tapNext, details: ["from": "ViewDepositView"])
                    appState.navigate(to: .openDoor, mode: .take)
                }
                .padding(.bottom, 30)

            } else {
                Spacer()
                Text("Item not found.")
                    .font(.poppins(.medium, size: 18))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            appState.sessionLog.log(.viewAppear, details: ["view": "ViewDepositView"])
        }
        .onDisappear {
            audioService.stopPlayback()
        }
    }
}
