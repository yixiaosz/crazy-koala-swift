// Views/Debug/SessionLogsView.swift
// List of all session log files with share, delete, multi-select (dev-plan §6.10)

import SwiftUI

struct SessionLogFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let fileSize: Int64
    let lineCount: Int
    let duration: String?
}

struct SessionLogsView: View {
    @State private var logFiles: [SessionLogFile] = []
    @State private var selectedFiles: Set<UUID> = []
    @State private var editMode: EditMode = .inactive
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    private let logsDir = DatabaseService.documentsURL.appendingPathComponent("logs")

    var body: some View {
        List(selection: $selectedFiles) {
            ForEach(logFiles) { file in
                NavigationLink {
                    SessionLogDetailView(logFile: file)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.name)
                            .font(.system(.body, design: .monospaced))
                        HStack(spacing: 12) {
                            Text(formatFileSize(file.fileSize))
                            Text("\(file.lineCount) entries")
                            if let duration = file.duration {
                                Text(duration)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteFile(file)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        shareItems = [file.url]
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Session Logs")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode == .active ? "Done" : "Select") {
                    editMode = editMode == .active ? .inactive : .active
                    if editMode == .inactive { selectedFiles.removeAll() }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if editMode == .active && !selectedFiles.isEmpty {
                    HStack {
                        Button {
                            shareSelectedFiles()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteSelectedFiles()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: shareItems)
        }
        .onAppear { loadLogFiles() }
    }

    // MARK: - Data Loading

    private func loadLogFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            logFiles = []
            return
        }

        logFiles = files
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // Newest first
            .compactMap { url in
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
                let duration = parseDuration(from: content)

                return SessionLogFile(
                    url: url,
                    name: url.lastPathComponent,
                    fileSize: size,
                    lineCount: lines.count,
                    duration: duration
                )
            }
    }

    private func parseDuration(from content: String) -> String? {
        // Look for duration_ms in SESSION_END line
        guard let range = content.range(of: "duration_ms=") else { return nil }
        let after = content[range.upperBound...]
        let msString = after.prefix(while: { $0.isNumber })
        guard let ms = Int(msString) else { return nil }
        let seconds = ms / 1000
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%dm %02ds", minutes, secs)
    }

    // MARK: - Actions

    private func deleteFile(_ file: SessionLogFile) {
        try? FileManager.default.removeItem(at: file.url)
        logFiles.removeAll { $0.id == file.id }
    }

    private func deleteSelectedFiles() {
        let toDelete = logFiles.filter { selectedFiles.contains($0.id) }
        for file in toDelete {
            try? FileManager.default.removeItem(at: file.url)
        }
        logFiles.removeAll { selectedFiles.contains($0.id) }
        selectedFiles.removeAll()
        editMode = .inactive
    }

    private func shareSelectedFiles() {
        let urls = logFiles.filter { selectedFiles.contains($0.id) }.map { $0.url }
        shareItems = urls
        showShareSheet = true
    }

    private func formatFileSize(_ size: Int64) -> String {
        if size < 1024 { return "\(size) B" }
        return String(format: "%.1f KB", Double(size) / 1024.0)
    }
}
