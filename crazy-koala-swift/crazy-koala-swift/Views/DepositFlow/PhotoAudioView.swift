// Views/DepositFlow/PhotoAudioView.swift
// Camera preview + audio recording, shared for deposit and take modes (dev-plan §6.3)

import SwiftUI

struct PhotoAudioView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var cameraService: CameraService
    @ObservedObject var audioService: AudioService

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isProcessing = false

    private var itemName: String { appState.currentItem?.name ?? "unknown" }

    var body: some View {
        VStack(spacing: 0) {
            YellowTitleBar(title: appState.mode == .deposit ? "Record Your Deposit" : "Record Your Take") {
                handleBack()
            }

            HStack(spacing: 20) {
                // MARK: - Left: Camera Preview
                VStack(spacing: 12) {
                    Text("Photo")
                        .font(.poppins(.bold, size: 18))

                    if cameraService.isSessionRunning {
                        CameraPreview(session: cameraService.session)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .cornerRadius(12)
                            .overlay(
                                Text("Camera Off")
                                    .font(.poppins(.regular, size: 16))
                                    .foregroundColor(.secondary)
                            )
                    }

                    HStack(spacing: 16) {
                        Button {
                            if cameraService.isSessionRunning {
                                cameraService.stopSession()
                            } else {
                                cameraService.startSession()
                            }
                        } label: {
                            Text(cameraService.isSessionRunning ? "Stop Preview" : "Start Preview")
                                .font(.poppins(.medium, size: 14))
                        }
                        .buttonStyle(.bordered)

                        if cameraService.isSessionRunning {
                            Button {
                                let orientation = UIApplication.shared.connectedScenes
                                    .compactMap { $0 as? UIWindowScene }
                                    .first?.interfaceOrientation ?? .portrait
                                Task {
                                    let _ = await cameraService.capturePhoto(orientation: orientation)
                                    if let url = cameraService.capturedImageURL {
                                        appState.sessionLog.log(.capturePhoto, details: ["path": url.lastPathComponent])
                                    }
                                }
                            } label: {
                                Text("Capture")
                                    .font(.poppins(.medium, size: 14))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    // Show captured photo thumbnail
                    if let url = cameraService.capturedImageURL,
                       let uiImage = UIImage(contentsOfFile: url.path) {
                        HStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 60)
                                .cornerRadius(8)
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Photo captured")
                                .font(.poppins(.regular, size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)

                Divider()

                // MARK: - Right: Audio Recording
                VStack(spacing: 12) {
                    Text("Audio Message")
                        .font(.poppins(.bold, size: 18))

                    Spacer()

                    BundleImage(name: "Microphone", maxWidth: 60, maxHeight: 60)

                    if audioService.isRecording {
                        Text("Recording... \(Int(audioService.recordingDuration))s")
                            .font(.poppins(.medium, size: 20))
                            .foregroundColor(.red)
                    } else if audioService.lastRecordingURL != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Audio recorded (\(Int(audioService.recordingDuration))s)")
                                .font(.poppins(.regular, size: 14))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Tap to record (max 60s)")
                            .font(.poppins(.regular, size: 14))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 16) {
                        if audioService.isRecording {
                            Button {
                                audioService.stopRecording()
                                appState.sessionLog.log(.recordAudioStop, details: [
                                    "duration_ms": "\(Int(audioService.recordingDuration * 1000))"
                                ])
                            } label: {
                                Text("Stop")
                                    .font(.poppins(.medium, size: 14))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button {
                                Task {
                                    let granted = await audioService.checkRecordPermission()
                                    if granted {
                                        audioService.startRecording()
                                        appState.sessionLog.log(.recordAudioStart)
                                    }
                                }
                            } label: {
                                Text("Record")
                                    .font(.poppins(.medium, size: 14))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }

                        // Play back recording
                        if let url = audioService.lastRecordingURL, !audioService.isRecording {
                            Button {
                                if audioService.isPlaying {
                                    audioService.stopPlayback()
                                } else {
                                    audioService.play(url: url)
                                    appState.sessionLog.log(.playAudio, details: ["file": url.lastPathComponent])
                                }
                            } label: {
                                BundleImage(name: "Trumpet", maxWidth: 30, maxHeight: 30)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
            }

            // MARK: - Bottom: Back / Next
            HStack {
                Button {
                    handleBack()
                } label: {
                    Text("Back")
                        .font(.poppins(.medium, size: 18))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                }

                Spacer()

                if isProcessing {
                    ProgressView()
                        .padding(.horizontal, 32)
                } else {
                    RoundedButton(title: "Next") {
                        handleNext()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            appState.sessionLog.log(.viewAppear, details: ["view": "PhotoAudioView"])
            Task {
                let granted = await cameraService.checkPermission()
                if granted {
                    cameraService.startSession()
                }
            }
        }
        .onDisappear {
            cameraService.stopSession()
            audioService.stopPlayback()
        }
    }

    // MARK: - Back (§6.3)

    private func handleBack() {
        appState.sessionLog.log(.tapBack, details: ["from": "PhotoAudioView"])
        // Discard temp files, stop camera/recording
        cameraService.discardCapturedPhoto()
        audioService.discardRecording()
        cameraService.stopSession()
        appState.goBack()
    }

    // MARK: - Next (§6.3)

    private func handleNext() {
        isProcessing = true
        appState.sessionLog.log(.tapNext, details: ["from": "PhotoAudioView"])

        let fm = FileManager.default
        let docs = DatabaseService.documentsURL
        let itemDir = docs.appendingPathComponent("data/\(itemName)")

        if appState.mode == .deposit {
            handleDepositNext(fm: fm, itemDir: itemDir)
        } else if appState.mode == .take {
            handleTakeNext(fm: fm, itemDir: itemDir)
        }
    }

    // MARK: - Deposit Mode Next (§6.3)

    private func handleDepositNext(fm: FileManager, itemDir: URL) {
        let photoDest = itemDir.appendingPathComponent("\(itemName)_deposit_photo.jpg")
        let audioDest = itemDir.appendingPathComponent("\(itemName)_deposit_audio.m4a")

        do {
            // 1. Create folder
            try fm.createDirectory(at: itemDir, withIntermediateDirectories: true)

            // 2. Photo: move captured or copy default
            if let capturedURL = cameraService.capturedImageURL {
                try fm.moveItem(at: capturedURL, to: photoDest)
            } else if let defaultURL = Bundle.main.url(forResource: "default_photo", withExtension: "png") {
                try fm.copyItem(at: defaultURL, to: photoDest)
            }

            // 3. Audio: move recorded or copy default
            if let recordedURL = audioService.lastRecordingURL {
                try fm.moveItem(at: recordedURL, to: audioDest)
            } else if let defaultURL = Bundle.main.url(forResource: "default_audio", withExtension: "m4a") {
                try fm.copyItem(at: defaultURL, to: audioDest)
            }

            // 4. Insert into DB (relative paths)
            let relPhoto = "data/\(itemName)/\(itemName)_deposit_photo.jpg"
            let relAudio = "data/\(itemName)/\(itemName)_deposit_audio.m4a"
            let inserted = try appState.itemStore.insertDeposit(
                name: itemName,
                depositPhotoPath: relPhoto,
                depositAudioPath: relAudio
            )

            // 5. Clear temp state
            cameraService.capturedImageURL = nil
            audioService.lastRecordingURL = nil
            appState.currentItem = inserted

            isProcessing = false

            // 6. Navigate to OpenDoorView
            appState.navigate(to: .openDoor)

        } catch {
            // Rollback: delete folder and contents (§6.3)
            try? fm.removeItem(at: itemDir)
            appState.sessionLog.log(.error, details: ["message": "Deposit save failed: \(error.localizedDescription)"])
            alertMessage = "Failed to save deposit: \(error.localizedDescription)"
            showAlert = true
            isProcessing = false
        }
    }

    // MARK: - Take Mode Next (§6.3)

    private func handleTakeNext(fm: FileManager, itemDir: URL) {
        let photoDest = itemDir.appendingPathComponent("\(itemName)_taken_photo.jpg")
        let audioDest = itemDir.appendingPathComponent("\(itemName)_taken_audio.m4a")

        do {
            // 1. Photo: move captured or copy default
            if let capturedURL = cameraService.capturedImageURL {
                try fm.moveItem(at: capturedURL, to: photoDest)
            } else if let defaultURL = Bundle.main.url(forResource: "default_photo", withExtension: "png") {
                try fm.copyItem(at: defaultURL, to: photoDest)
            }

            // 2. Audio: move recorded or copy default
            if let recordedURL = audioService.lastRecordingURL {
                try fm.moveItem(at: recordedURL, to: audioDest)
            } else if let defaultURL = Bundle.main.url(forResource: "default_audio", withExtension: "m4a") {
                try fm.copyItem(at: defaultURL, to: audioDest)
            }

            // 3. Update DB with taken paths
            guard let itemId = appState.currentItem?.id else {
                throw NSError(domain: "PhotoAudioView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No current item ID"])
            }
            let relPhoto = "data/\(itemName)/\(itemName)_taken_photo.jpg"
            let relAudio = "data/\(itemName)/\(itemName)_taken_audio.m4a"
            try appState.itemStore.updateTaken(
                itemId: itemId,
                takenPhotoPath: relPhoto,
                takenAudioPath: relAudio
            )

            // 4. Clear temp state
            cameraService.capturedImageURL = nil
            audioService.lastRecordingURL = nil

            isProcessing = false

            // 5. Return to mode-selection (session stays active)
            appState.returnToModeSelection()

        } catch {
            // Rollback: delete taken files only (§6.3)
            try? fm.removeItem(at: photoDest)
            try? fm.removeItem(at: audioDest)
            appState.sessionLog.log(.error, details: ["message": "Take save failed: \(error.localizedDescription)"])
            alertMessage = "Failed to save take: \(error.localizedDescription)"
            showAlert = true
            isProcessing = false
        }
    }
}
