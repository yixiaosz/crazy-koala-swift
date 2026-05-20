// Services/AudioService.swift
// AVAudioRecorder + AVAudioPlayer wrapper, M4A/AAC only (dev-plan §5.3)

import AVFoundation
import Combine
import Foundation
import UIKit

final class AudioService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionDenied = false

    // MARK: - Properties

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    /// URL of the last completed recording in tmp/
    var lastRecordingURL: URL?

    /// Maximum recording duration in seconds (§5.3)
    private let maxDuration: TimeInterval = 60

    /// AAC recording settings (§5.3: M4A/AAC, 44.1kHz, 1 channel, 64-96 kbps)
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 80000, // 80 kbps (within 64-96 range)
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    // MARK: - Audio Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("[AudioService] Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Permission (§5.3)

    /// Check and request microphone permission. Returns true if granted.
    func checkRecordPermission() async -> Bool {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            return true
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        case .denied:
            await MainActor.run { permissionDenied = true }
            return false
        @unknown default:
            return false
        }
    }

    /// Open Settings so the user can grant microphone access
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Recording

    func startRecording() {
        configureSession()

        // Generate tmp file URL
        let tmpDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(UUID().uuidString).m4a"
        let url = tmpDir.appendingPathComponent(fileName)

        do {
            recorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            recorder?.delegate = self
            recorder?.record(forDuration: maxDuration) // Auto-stops at 60s
            lastRecordingURL = url
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0

            // Timer for UI updates
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }

            print("[AudioService] Recording started: \(fileName)")
        } catch {
            print("[AudioService] Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        print("[AudioService] Recording stopped, duration: \(String(format: "%.1f", recordingDuration))s")
    }

    /// Discard the current temporary recording file
    func discardRecording() {
        stopRecording()
        if let url = lastRecordingURL {
            try? FileManager.default.removeItem(at: url)
            lastRecordingURL = nil
            print("[AudioService] Recording discarded")
        }
        recordingDuration = 0
    }

    // MARK: - Playback

    /// Play audio from a file URL
    func play(url: URL) {
        stopPlayback()
        configureSession()

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
            print("[AudioService] Playing: \(url.lastPathComponent)")
        } catch {
            print("[AudioService] Failed to play audio: \(error)")
        }
    }

    /// Play a bundled audio file by name (e.g., "start_interact" for start_interact.m4a)
    func playBundled(name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            print("[AudioService] Bundled audio not found: \(name).m4a")
            return
        }
        play(url: url)
    }

    func stopPlayback() {
        guard isPlaying else { return }
        player?.stop()
        player = nil
        isPlaying = false
    }

    // MARK: - Cleanup

    /// Stop all activity (recording + playback)
    func stopAll() {
        discardRecording()
        stopPlayback()
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.isRecording = false
            if !flag {
                print("[AudioService] Recording finished unsuccessfully")
                self.lastRecordingURL = nil
            } else {
                print("[AudioService] Recording finished successfully")
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
}
