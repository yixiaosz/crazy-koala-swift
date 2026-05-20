// Views/Memories/DetailView.swift
// Side-by-side deposit/take detail view (dev-plan §6.8)

import SwiftUI

struct DetailView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioService: AudioService

    @State private var playingURL: URL?

    private var item: Item? { appState.currentItem }

    var body: some View {
        VStack(spacing: 0) {
            YellowTitleBar(title: item?.name ?? "Memory Details") {
                appState.sessionLog.log(.tapBack, details: ["from": "DetailView"])
                appState.goBack()
            }

            if let item {
                HStack(spacing: 20) {
                    // MARK: - Left: Deposit
                    VStack(spacing: 12) {
                        Text("Deposit")
                            .font(.poppins(.bold, size: 20))

                        photoView(relativePath: item.depositPhotoPath)

                        if let date = item.depositCreatedAt {
                            Text(Item.displayDateFormatter.string(from: date))
                                .font(.poppins(.regular, size: 14))
                                .foregroundColor(.secondary)
                        }

                        audioButton(relativePath: item.depositAudioPath, label: "Play Deposit Audio")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()

                    Divider()

                    // MARK: - Right: Take
                    VStack(spacing: 12) {
                        Text("Take")
                            .font(.poppins(.bold, size: 20))

                        photoView(relativePath: item.takenPhotoPath)

                        if let date = item.takenCreatedAt {
                            Text(Item.displayDateFormatter.string(from: date))
                                .font(.poppins(.regular, size: 14))
                                .foregroundColor(.secondary)
                        }

                        audioButton(relativePath: item.takenAudioPath, label: "Play Take Audio")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                Spacer()
                Text("Memory not found.")
                    .font(.poppins(.medium, size: 18))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            appState.sessionLog.log(.viewAppear, details: ["view": "DetailView"])
        }
        .onDisappear {
            audioService.stopPlayback()
            playingURL = nil
        }
        .onChange(of: audioService.isPlaying) { _, isPlaying in
            if !isPlaying { playingURL = nil }
        }
    }

    // MARK: - Photo

    @ViewBuilder
    private func photoView(relativePath: String?) -> some View {
        if let path = relativePath {
            let absPath = DatabaseService.resolveAbsolutePath(path)
            if let uiImage = UIImage(contentsOfFile: absPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
            } else {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(height: 200)
            .cornerRadius(12)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            )
    }

    // MARK: - Audio

    @ViewBuilder
    private func audioButton(relativePath: String?, label: String) -> some View {
        if let path = relativePath {
            let absPath = DatabaseService.resolveAbsolutePath(path)
            let url = URL(fileURLWithPath: absPath)
            let isThisPlaying = audioService.isPlaying && playingURL == url
            Button {
                if isThisPlaying {
                    audioService.stopPlayback()
                    playingURL = nil
                } else {
                    audioService.stopPlayback()
                    audioService.play(url: url)
                    playingURL = url
                    appState.sessionLog.log(.playAudio, details: ["file": url.lastPathComponent])
                }
            } label: {
                HStack {
                    BundleImage(name: "Trumpet", maxWidth: 24, maxHeight: 24)
                    Text(isThisPlaying ? "Stop Audio" : label)
                        .font(.poppins(.medium, size: 14))
                }
            }
            .buttonStyle(.bordered)
            .animation(.none, value: isThisPlaying)
        }
    }
}
