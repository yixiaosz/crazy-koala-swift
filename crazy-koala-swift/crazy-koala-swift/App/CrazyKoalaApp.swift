// App/CrazyKoalaApp.swift
// @main entry point for the Crazy Koala iPad app (dev-plan §3)

import SwiftUI

@main
struct CrazyKoalaApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appState)
                .onAppear {
                    // Start TCP client on launch
                    appState.tcpClient.start()
                    // Configure camera session (permission requested on first use)
                    appState.cameraService.configureSession()
                }
        }
    }
}
