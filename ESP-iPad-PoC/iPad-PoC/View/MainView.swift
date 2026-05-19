import SwiftUI

struct MainView: View {
    @StateObject var viewModel = AppViewModel()
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Text("ESP32 TCP PoC")
                    .font(.largeTitle)
                    .bold()
                
                // Connection status badge
                Text(viewModel.tcpClient.state.description)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(stateColor(viewModel.tcpClient.state))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                // Red LED indicator
                RoundedRectangle(cornerRadius: 24)
                    .fill(viewModel.isLedActive ? Color.red : Color.gray.opacity(0.3))
                    .frame(width: 200, height: 140)
                    .overlay(
                        Text(viewModel.isLedActive ? "LED ON" : "OFF")
                            .font(.title2)
                            .bold()
                            .foregroundColor(viewModel.isLedActive ? .white : .primary)
                    )
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isLedActive)
                
                // Blue BOOT signal indicator
                RoundedRectangle(cornerRadius: 24)
                    .fill(viewModel.isBootSignalActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 200, height: 140)
                    .overlay(
                        Text(viewModel.isBootSignalActive ? "BOOT SIG" : "—")
                            .font(.title2)
                            .bold()
                            .foregroundColor(viewModel.isBootSignalActive ? .white : .primary)
                    )
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isBootSignalActive)
                
                Spacer()
                
                NavigationLink(destination: DebugView(viewModel: viewModel)) {
                    Label("Debug Diagnostics", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.connect()
                } else if newPhase == .background {
                    viewModel.disconnect()
                }
            }
        }
    }
    
    private func stateColor(_ state: ConnectionState) -> Color {
        switch state {
        case .disconnected: return .gray
        case .resolving: return .yellow
        case .connecting: return .orange
        case .connected: return .green
        case .reconnecting: return .red
        }
    }
}
