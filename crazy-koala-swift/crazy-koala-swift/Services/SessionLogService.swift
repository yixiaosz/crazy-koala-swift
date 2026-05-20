// Services/SessionLogService.swift
// Per-session timestamped action logging with crash recovery (dev-plan §5.5)

import Foundation

// MARK: - Session Trigger

enum SessionTrigger: String {
    case tapStart = "tap_start"
    case esp32Button = "esp32_button"
}

// MARK: - Log Actions (Exhaustive list from §5.5)

enum LogAction: String {
    case sessionStart = "SESSION_START"
    case selectMode = "SELECT_MODE"
    case viewAppear = "VIEW_APPEAR"
    case inputName = "INPUT_NAME"
    case capturePhoto = "CAPTURE_PHOTO"
    case recordAudioStart = "RECORD_AUDIO_START"
    case recordAudioStop = "RECORD_AUDIO_STOP"
    case playAudio = "PLAY_AUDIO"
    case tapNext = "TAP_NEXT"
    case tapBack = "TAP_BACK"
    case tapDone = "TAP_DONE"
    case doorUnlock = "DOOR_UNLOCK"
    case doorLock = "DOOR_LOCK"
    case selectItem = "SELECT_ITEM"
    case esp32Tx = "ESP32_TX"
    case esp32Rx = "ESP32_RX"
    case error = "ERROR"
    case sessionEnd = "SESSION_END"
    case sessionAborted = "SESSION_ABORTED"
}

// MARK: - SessionLogService

final class SessionLogService {
    private static let activeLogKey = "activeSessionLogURL"

    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.crazykoala.sessionlog", qos: .utility)

    private var fileHandle: FileHandle?
    private var sessionStartTime: Date?
    private(set) var currentLogURL: URL?
    private(set) var isSessionActive: Bool = false

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss_SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Init + Crash Recovery (§5.5)

    init() {
        recoverFromCrashIfNeeded()
    }

    /// On app launch, check if a previous session was not properly ended.
    /// If so, append SESSION_ABORTED and clean up.
    private func recoverFromCrashIfNeeded() {
        guard let urlString = UserDefaults.standard.string(forKey: Self.activeLogKey) else { return }
        let url = URL(fileURLWithPath: urlString)

        guard fileManager.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: Self.activeLogKey)
            return
        }

        // Check if the file already ends with SESSION_END
        if let contents = try? String(contentsOf: url, encoding: .utf8),
           !contents.contains("[SESSION_END]") {
            // Append SESSION_ABORTED
            let timestamp = Self.timestampFormatter.string(from: Date())
            let line = "[\(timestamp)] [SESSION_ABORTED] reason=app_killed_or_crash\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
            print("[SessionLogService] Recovered crashed session: \(url.lastPathComponent)")
        }

        UserDefaults.standard.removeObject(forKey: Self.activeLogKey)
    }

    // MARK: - Session Lifecycle

    func startSession(trigger: SessionTrigger) {
        guard !isSessionActive else {
            print("[SessionLogService] Session already active, ignoring startSession")
            return
        }

        let now = Date()
        sessionStartTime = now

        // Create log file: Documents/logs/session_YYYY-MM-DD_HH-mm-ss_SSS.txt
        let logsDir = DatabaseService.documentsURL.appendingPathComponent("logs")
        let fileName = "session_\(Self.fileNameFormatter.string(from: now)).txt"
        let logURL = logsDir.appendingPathComponent(fileName)

        fileManager.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logURL)
        currentLogURL = logURL
        isSessionActive = true

        // Store in UserDefaults for crash recovery
        UserDefaults.standard.set(logURL.path, forKey: Self.activeLogKey)

        // Write first entry
        log(.sessionStart, details: ["trigger": trigger.rawValue])
        print("[SessionLogService] Session started: \(fileName)")
    }

    func log(_ action: LogAction, details: [String: String]? = nil) {
        guard isSessionActive, let handle = fileHandle else { return }

        let timestamp = Self.timestampFormatter.string(from: Date())
        var line = "[\(timestamp)] [\(action.rawValue)]"

        if let details = details {
            let sorted = details.sorted { $0.key < $1.key }
            for (key, value) in sorted {
                line += " \(key)=\(value)"
            }
        }

        line += "\n"

        // Immediate disk append on background queue — no buffering (§5.5)
        logQueue.sync {
            if let data = line.data(using: .utf8) {
                handle.seekToEndOfFile()
                handle.write(data)
            }
        }
    }

    func endSession() {
        guard isSessionActive else { return }

        // Calculate duration
        var details: [String: String] = [:]
        if let start = sessionStartTime {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            details["duration_ms"] = "\(durationMs)"
        }

        log(.sessionEnd, details: details)

        // Clean up
        logQueue.sync {
            try? fileHandle?.close()
        }
        fileHandle = nil
        currentLogURL = nil
        sessionStartTime = nil
        isSessionActive = false

        UserDefaults.standard.removeObject(forKey: Self.activeLogKey)
        print("[SessionLogService] Session ended")
    }
}
