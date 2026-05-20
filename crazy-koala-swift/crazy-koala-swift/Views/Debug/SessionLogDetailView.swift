// Views/Debug/SessionLogDetailView.swift
// Full log content viewer with share (dev-plan §6.10)

import SwiftUI

struct SessionLogDetailView: View {
    let logFile: SessionLogFile

    @State private var content: String = "Loading..."
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(logFile.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [logFile.url])
        }
        .onAppear {
            content = (try? String(contentsOf: logFile.url, encoding: .utf8)) ?? "Failed to read log file."
        }
    }
}
