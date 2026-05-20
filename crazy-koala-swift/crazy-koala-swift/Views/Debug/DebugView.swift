// Views/Debug/DebugView.swift
// ESP32 diagnostics, session logs entrance, export/erase data (dev-plan §6.9)

import GRDB
import SwiftUI

struct DebugView: View {
    @ObservedObject var tcpClient: TCPClientService
    let sessionLogService: SessionLogService

    @State private var showEraseConfirmation = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    @Environment(\.dismiss) private var dismiss

    private let validCommands = Array("0123456789ABCDEF")

    var body: some View {
        NavigationStack {
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
                    sessionLogsSection
                    exportDataSection
                    eraseDataSection
                }
                .padding()
            }
            .navigationTitle("Debug")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Erase All Data", isPresented: $showEraseConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Erase Everything", role: .destructive) { eraseAllData() }
            } message: {
                Text("This will permanently delete all items, photos, audio recordings, and session logs. This cannot be undone.")
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: shareItems)
            }
        }
    }

    // MARK: - Connection State

    private var connectionStateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection State Machine")
                .font(.poppins(.bold, size: 16))
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 12, height: 12)
                Text(tcpClient.connectionState.displayText)
                    .font(.system(.body, design: .monospaced))
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }

    // MARK: - RX / TX

    private var rxTxSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last RX").font(.caption).foregroundColor(.secondary)
                Text(tcpClient.lastRx?.description ?? "—")
                    .font(.system(.title2, design: .monospaced))
                Text(tcpClient.lastRx?.timestampString ?? "")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Last TX").font(.caption).foregroundColor(.secondary)
                Text(tcpClient.lastTx?.description ?? "—")
                    .font(.system(.title2, design: .monospaced))
                Text(tcpClient.lastTx?.timestampString ?? "")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - FPS

    private var fpsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame Counter & FPS (5s)")
                .font(.poppins(.bold, size: 16))
            HStack(spacing: 4) {
                ForEach(Array(tcpClient.fpsHistory.enumerated()), id: \.offset) { _, count in
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

    // MARK: - Hex Dump

    private var hexDumpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Packet Hex Dump (last 10)")
                .font(.poppins(.bold, size: 16))
            Text(tcpClient.rawHexDump.isEmpty ? "—" : tcpClient.rawHexDump.map { String(format: "0x%02X", $0) }.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Network Vitals

    private var networkVitalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network Vitals")
                .font(.poppins(.bold, size: 16))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Local IP").foregroundColor(.secondary)
                    Text(tcpClient.localIPAddress)
                }
                GridRow {
                    Text("Target IP").foregroundColor(.secondary)
                    Text(TCPClientService.host)
                }
                GridRow {
                    Text("Target Port").foregroundColor(.secondary)
                    Text("\(TCPClientService.port)")
                }
            }
            .font(.system(.body, design: .monospaced))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Force Reconnect

    private var forceReconnectSection: some View {
        Button {
            tcpClient.forceReconnect()
        } label: {
            Label("Force Reconnect", systemImage: "arrow.clockwise")
                .font(.poppins(.medium, size: 16))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }

    // MARK: - Error Log

    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error Log (last 20)")
                .font(.poppins(.bold, size: 16))
            if tcpClient.errorLog.isEmpty {
                Text("No errors")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tcpClient.errorLog) { entry in
                        Text(entry.displayText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Command Injector

    private var commandInjectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual Command Injector")
                .font(.poppins(.bold, size: 16))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(validCommands, id: \.self) { char in
                    Button {
                        tcpClient.send(char)
                    } label: {
                        Text(String(char))
                            .font(.system(.title2, design: .monospaced).bold())
                            .frame(maxWidth: .infinity, minHeight: 50)
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

    // MARK: - Session Logs

    private var sessionLogsSection: some View {
        NavigationLink {
            SessionLogsView()
        } label: {
            Label("Session Logs", systemImage: "doc.text")
                .font(.poppins(.medium, size: 16))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
    }

    // MARK: - Export All Data (§6.9)

    private var exportDataSection: some View {
        Button {
            exportAllData()
        } label: {
            Label("Export All Data", systemImage: "square.and.arrow.up")
                .font(.poppins(.medium, size: 16))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    // MARK: - Erase All Data (§6.9)

    private var eraseDataSection: some View {
        Button {
            showEraseConfirmation = true
        } label: {
            Label("Erase All Data", systemImage: "trash")
                .font(.poppins(.medium, size: 16))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch tcpClient.connectionState {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .reconnecting: return .red
        }
    }

    private func exportAllData() {
        let dataDir = DatabaseService.documentsURL.appendingPathComponent("data")
        guard FileManager.default.fileExists(atPath: dataDir.path) else {
            print("[DebugView] No data directory to export")
            return
        }

        // Use NSFileCoordinator to create a zip of the data directory
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: dataDir, options: .forUploading, error: &error) { zipURL in
            // Copy zip to tmp so it persists after coordination ends
            let tmpZip = FileManager.default.temporaryDirectory.appendingPathComponent("crazy_koala_data_export.zip")
            try? FileManager.default.removeItem(at: tmpZip)
            try? FileManager.default.copyItem(at: zipURL, to: tmpZip)

            DispatchQueue.main.async {
                self.shareItems = [tmpZip]
                self.showShareSheet = true
            }
        }
        if let error {
            print("[DebugView] Export error: \(error)")
        }
    }

    private func eraseAllData() {
        let fm = FileManager.default
        let docs = DatabaseService.documentsURL

        // 1. Delete all contents of Documents/data/
        let dataDir = docs.appendingPathComponent("data")
        if let contents = try? fm.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fm.removeItem(at: item)
            }
        }

        // 2. Delete all rows from items table
        try? DatabaseService.shared.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM items")
        }

        // 3. Delete all session logs
        let logsDir = docs.appendingPathComponent("logs")
        if let contents = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fm.removeItem(at: item)
            }
        }

        // 4. Clear active session state
        if sessionLogService.isSessionActive {
            sessionLogService.endSession()
        }

        print("[DebugView] All data erased")
    }
}

// MARK: - UIActivityViewController Bridge

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
