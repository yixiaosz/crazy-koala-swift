// Models/Item.swift
// GRDB-compatible model matching the existing SQLite schema (dev-plan §4.1)

import Foundation
import GRDB

struct Item: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var depositPhotoPath: String?
    var depositAudioPath: String?
    var depositCreatedAt: Date?
    var takenPhotoPath: String?
    var takenAudioPath: String?
    var takenCreatedAt: Date?

    // Map Swift property names to the exact database column names
    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case name
        case depositPhotoPath = "deposit_photo_path"
        case depositAudioPath = "deposit_audio_path"
        case depositCreatedAt = "deposit_created_at"
        case takenPhotoPath = "taken_photo_path"
        case takenAudioPath = "taken_audio_path"
        case takenCreatedAt = "taken_created_at"
    }

    static let databaseTableName = "items"

    // Use the SQLite TEXT date format for encoding/decoding
    static let databaseDateDecodingStrategy: DatabaseDateDecodingStrategy = .formatted(Item.sqliteDateFormatter)
    static let databaseDateEncodingStrategy: DatabaseDateEncodingStrategy = .formatted(Item.sqliteDateFormatter)

    /// DateFormatter matching SQLite's DEFAULT CURRENT_TIMESTAMP format (UTC, for DB storage)
    static let sqliteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// DateFormatter for displaying timestamps in the device's local timezone
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    // GRDB auto-generates id on insert when nil
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
