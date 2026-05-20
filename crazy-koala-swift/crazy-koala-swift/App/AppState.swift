// App/AppState.swift
// Shared app state and navigation (dev-plan §8)

import Combine
import SwiftUI

// MARK: - Mode Enum

enum Mode: String {
    case deposit
    case take
    case memories
}

// MARK: - Navigation Destinations

enum NavDestination: Hashable {
    case inputName
    case depositPrompt
    case photoAudio
    case openDoor
    case selectItem
    case viewDeposit
    case takePrompt
    case gallery
    case detail
}

// MARK: - App State

final class AppState: ObservableObject {
    @Published var currentItem: Item?
    @Published var mode: Mode?
    @Published var isSessionActive: Bool = false
    @Published var navigationPath = NavigationPath()

    let tcpClient = TCPClientService()
    let sessionLog = SessionLogService()
    let audioService = AudioService()
    let cameraService = CameraService()
    let itemStore = ItemStore()

    /// Navigate to a destination and set mode
    func navigate(to destination: NavDestination, mode: Mode? = nil) {
        if let mode { self.mode = mode }
        navigationPath.append(destination)
    }

    /// Pop back one screen
    func goBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    /// Return to mode-selection (pop all flow screens)
    func returnToModeSelection() {
        navigationPath = NavigationPath()
        mode = nil
    }

    /// Start a new session
    func startSession(trigger: SessionTrigger) {
        guard !isSessionActive else { return }
        isSessionActive = true
        sessionLog.startSession(trigger: trigger)
        audioService.playBundled(name: "start_interact")
    }

    /// End the current session
    func endSession() {
        sessionLog.endSession()
        navigationPath = NavigationPath()
        mode = nil
        currentItem = nil
        isSessionActive = false
    }
}
