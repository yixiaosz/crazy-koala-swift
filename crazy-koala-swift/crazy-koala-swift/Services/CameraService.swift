// Services/CameraService.swift
// AVCaptureSession wrapper + photo capture + UIViewRepresentable preview (dev-plan §5.2)

@preconcurrency import AVFoundation
import Combine
import SwiftUI
import UIKit

final class CameraService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isSessionRunning = false
    @Published var permissionDenied = false
    @Published var capturedImageURL: URL?

    // MARK: - Capture Properties

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.crazykoala.camera")
    private var photoContinuation: CheckedContinuation<URL?, Never>?

    // MARK: - Permission (§5.2)

    func checkPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            await MainActor.run { permissionDenied = true }
            return false
        @unknown default:
            return false
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Session Setup

    func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Front-facing camera (§5.2)
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("[CameraService] No front camera available")
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
            } catch {
                print("[CameraService] Failed to configure session: \(error)")
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - Start / Stop (§5.2)

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
            print("[CameraService] Session started")
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
            print("[CameraService] Session stopped")
        }
    }

    // MARK: - Capture Photo (§5.2)

    /// Capture a photo and return the tmp file URL as JPEG. Returns nil on failure.
    /// Pass the current interface orientation so the saved image matches the iPad orientation.
    func capturePhoto(orientation: UIInterfaceOrientation = .portrait) async -> URL? {
        await withCheckedContinuation { continuation in
            self.photoContinuation = continuation
            sessionQueue.async { [self] in
                // Set rotation angle on the photo output connection to match device orientation
                if let connection = self.photoOutput.connection(with: .video) {
                    let angle: CGFloat
                    switch orientation {
                    case .portrait: angle = 270
                    case .portraitUpsideDown: angle = 90
                    case .landscapeLeft: angle = 180
                    case .landscapeRight: angle = 0
                    default: angle = 270
                    }
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                }
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    /// Discard the captured photo tmp file
    func discardCapturedPhoto() {
        if let url = capturedImageURL {
            try? FileManager.default.removeItem(at: url)
            capturedImageURL = nil
            print("[CameraService] Captured photo discarded")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            print("[CameraService] Photo capture error: \(error)")
            Task { @MainActor in
                self.photoContinuation?.resume(returning: nil)
                self.photoContinuation = nil
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.85) else {
            print("[CameraService] Failed to process photo data")
            Task { @MainActor in
                self.photoContinuation?.resume(returning: nil)
                self.photoContinuation = nil
            }
            return
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let fileName = "capture_\(UUID().uuidString).jpg"
        let url = tmpDir.appendingPathComponent(fileName)

        do {
            try jpegData.write(to: url)
            print("[CameraService] Photo captured: \(fileName)")
            Task { @MainActor in
                self.capturedImageURL = url
                self.photoContinuation?.resume(returning: url)
                self.photoContinuation = nil
            }
        } catch {
            print("[CameraService] Failed to save photo: \(error)")
            Task { @MainActor in
                self.photoContinuation?.resume(returning: nil)
                self.photoContinuation = nil
            }
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.updateOrientation()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.updateOrientation()
    }
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(0) else { return }

        let angle: CGFloat
        guard let scene = window?.windowScene else {
            connection.videoRotationAngle = 0
            return
        }

        switch scene.interfaceOrientation {
        case .portrait:
            angle = 270
        case .portraitUpsideDown:
            angle = 90
        case .landscapeLeft:
            angle = 180
        case .landscapeRight:
            angle = 0
        default:
            angle = 270
        }

        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
