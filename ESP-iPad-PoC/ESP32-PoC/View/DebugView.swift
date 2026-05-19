import SwiftUI

struct DebugView: View {
    @ObservedObject var viewModel: AppViewModel
    
    private let validCommands = Array("0123456789ABCDEF")
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionStateSection
                rxTxSection
                fpsSection
                hexDumpSection
                networkVitalsSection
                forceReconnectSection
                errorLogSection
                commandInjectorSection
            }
            .padding()
        }
        .navigationTitle("Debug")
    }
    
    // MARK: - Sections
    private var connectionStateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection State Machine")
                .font(.headline)
            HStack {
                Circle()
                    .fill(stateColor(viewModel.tcpClient.state))
                    .frame(width: 12, height: 12)
                Text(viewModel.tcpClient.state.description)
                    .font(.system(.body, design: .monospaced))
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }
    
    private var rxTxSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last RX").font(.caption).foregroundColor(.secondary)
                Text(viewModel.tcpClient.lastRx?.description ?? "—")
                    .font(.system(.title2, design: .monospaced))
                Text(viewModel.tcpClient.lastRx?.timestampString ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Last TX").font(.caption).foregroundColor(.secondary)
                Text(viewModel.tcpClient.lastTx?.description ?? "—")
                    .font(.system(.title2, design: .monospaced))
                Text(viewModel.tcpClient.lastTx?.timestampString ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private var fpsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame Counter & FPS (5s)")
                .font(.headline)
            HStack(spacing: 4) {
                ForEach(Array(viewModel.tcpClient.fpsHistory.enumerated()), id: \.offset) { index, count in
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(height: CGFloat(min(count, 50)) * 2 + 2)
                        Text("\(count)")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private var hexDumpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Packet Hex Dump (last 10)")
                .font(.headline)
            Text(viewModel.tcpClient.rawHexDump.isEmpty ? "—" : viewModel.tcpClient.rawHexDump.map { String(format: "0x%02X", $0) }.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private var networkVitalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network Vitals")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Local IP").foregroundColor(.secondary)
                    Text(viewModel.tcpClient.localIPAddress)
                }
                GridRow {
                    Text("Target IP").foregroundColor(.secondary)
                    Text(TCPClient.sharedHost)
                }
                GridRow {
                    Text("Target Port").foregroundColor(.secondary)
                    Text("\(TCPClient.sharedPort)")
                }
            }
            .font(.system(.body, design: .monospaced))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private var forceReconnectSection: some View {
        Button {
            viewModel.forceReconnect()
        } label: {
            Label("Force Reconnect", systemImage: "arrow.clockwise")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }
    
    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error Log (last 20)")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.tcpClient.errorLog) { entry in
                    Text(entry.displayText)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private var commandInjectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual Command Injector")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(validCommands, id: \.self) { char in
                    Button {
                        viewModel.sendCommand(char)
                    } label: {
                        Text(String(char))
                            .font(.title2)
                            .bold()
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
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
