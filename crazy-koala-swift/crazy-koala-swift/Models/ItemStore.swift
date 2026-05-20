// Models/ItemStore.swift
// CRUD operations + file validation (dev-plan §4.2, §4.3)

import Foundation
import GRDB

final class ItemStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseService.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - 1. Insert Deposit (§4.2.1)

    /// Insert a new item with deposit paths. Paths must be relative to Documents/.
    @discardableResult
    func insertDeposit(name: String, depositPhotoPath: String?, depositAudioPath: String?) throws -> Item {
        let item = Item(
            name: name,
            depositPhotoPath: depositPhotoPath,
            depositAudioPath: depositAudioPath,
            depositCreatedAt: Date()
        )
        let insertedItem = try dbQueue.write { db in
            try item.inserted(db)
        }
        print("[ItemStore] Inserted deposit: id=\(insertedItem.id ?? -1), name=\(name)")
        return insertedItem
    }

    // MARK: - 2. Update Taken (§4.2.2)

    /// Update an existing item by id with taken paths and timestamp.
    /// Uses id instead of name because name has no UNIQUE constraint.
    func updateTaken(itemId: Int64, takenPhotoPath: String?, takenAudioPath: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE items
                    SET taken_photo_path = ?,
                        taken_audio_path = ?,
                        taken_created_at = CURRENT_TIMESTAMP
                    WHERE id = ?
                    """,
                arguments: [takenPhotoPath, takenAudioPath, itemId]
            )
        }
        print("[ItemStore] Updated taken: id=\(itemId)")
    }

    // MARK: - 3. Fetch All Items (§4.2.3)

    /// Fetch items where both deposit and taken photos exist (completed memories).
    /// Validates that both photo files actually exist on disk.
    func fetchAllItems() throws -> [Item] {
        let items: [Item] = try dbQueue.read { db in
            try Item
                .filter(Item.CodingKeys.depositPhotoPath != nil)
                .filter(Item.CodingKeys.takenPhotoPath != nil)
                .fetchAll(db)
        }

        return items.filter { item in
            guard let depositPath = item.depositPhotoPath,
                  let takenPath = item.takenPhotoPath else { return false }

            let depositExists = DatabaseService.fileExists(atRelativePath: depositPath)
            let takenExists = DatabaseService.fileExists(atRelativePath: takenPath)

            if !depositExists || !takenExists {
                print("[ItemStore] Skipping item '\(item.name)' (id=\(item.id ?? -1)): missing files — deposit=\(depositExists), taken=\(takenExists)")
                return false
            }
            return true
        }
    }

    // MARK: - 4. Fetch Unretrieved Items (§4.2.4)

    /// Fetch items where taken_created_at IS NULL (not yet retrieved).
    /// Validates that deposit_photo_path exists on disk.
    func fetchUnretrievedItems() throws -> [(name: String, photoPath: String)] {
        let items: [Item] = try dbQueue.read { db in
            try Item
                .filter(Item.CodingKeys.takenCreatedAt == nil)
                .fetchAll(db)
        }

        return items.compactMap { item in
            guard let depositPath = item.depositPhotoPath else {
                print("[ItemStore] Skipping unretrieved item '\(item.name)': no deposit photo path")
                return nil
            }
            guard DatabaseService.fileExists(atRelativePath: depositPath) else {
                print("[ItemStore] Skipping unretrieved item '\(item.name)': deposit photo missing on disk")
                return nil
            }
            return (name: item.name, photoPath: depositPath)
        }
    }

    // MARK: - 5. Fetch Item Details (§4.2.5)

    /// Fetch a single item by name (LIMIT 1). Returns nil if not found.
    func fetchItemDetails(name: String) throws -> Item? {
        try dbQueue.read { db in
            try Item
                .filter(Item.CodingKeys.name == name)
                .fetchOne(db)
        }
    }
}
