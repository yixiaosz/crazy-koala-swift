// Services/DatabaseService.swift
// GRDB DatabaseQueue setup + table creation (dev-plan §5.1, §4.1)

import Foundation
import GRDB

final class DatabaseService {
    static let shared = DatabaseService()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dbURL = documentsURL.appendingPathComponent("items.db")

            // Create Documents/data/ directory for item files
            let dataURL = documentsURL.appendingPathComponent("data")
            try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)

            // Create Documents/logs/ directory for session logs
            let logsURL = documentsURL.appendingPathComponent("logs")
            try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)

            var config = Configuration()

            // Configure date format to match SQLite's DEFAULT CURRENT_TIMESTAMP (TEXT: "YYYY-MM-DD HH:MM:SS")
            // Critical: GRDB default uses timeIntervalSinceReferenceDate which is incompatible (§4.1)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(identifier: "UTC")

            config.prepareDatabase { db in
                db.add(function: DatabaseFunction("CURRENT_TIMESTAMP", argumentCount: 0, pure: false) { _ in
                    return dateFormatter.string(from: Date())
                })
            }

            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

            // Register date encoding/decoding strategy
            try dbQueue.write { db in
                // Create the items table with the exact schema from the dev plan §4.1
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS items (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        deposit_photo_path TEXT,
                        deposit_audio_path TEXT,
                        deposit_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                        taken_photo_path TEXT,
                        taken_audio_path TEXT,
                        taken_created_at TIMESTAMP
                    )
                    """)
            }

            print("[DatabaseService] Database initialized at \(dbURL.path)")
        } catch {
            fatalError("[DatabaseService] Failed to initialize database: \(error)")
        }
    }

    /// The app's Documents directory URL
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Resolve a relative path (stored in DB) to an absolute path
    static func resolveAbsolutePath(_ relativePath: String) -> String {
        documentsURL.appendingPathComponent(relativePath).path
    }

    /// Check if a file exists at the given relative path (relative to Documents/)
    static func fileExists(atRelativePath relativePath: String) -> Bool {
        let absolutePath = resolveAbsolutePath(relativePath)
        return FileManager.default.fileExists(atPath: absolutePath)
    }
}
