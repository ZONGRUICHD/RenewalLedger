import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct RenewalBackupRecord: Codable {
    let id: UUID
    let name: String
    let amount: Double
    let currencyCode: String
    let cycleRawValue: String
    let categoryRawValue: String
    let nextRenewalDate: Date
    let reminderEnabled: Bool
    let note: String
    let createdAt: Date
    let updatedAt: Date

    init(item: RenewalItem) {
        id = item.id
        name = item.name
        amount = item.amount
        currencyCode = item.currencyCode
        cycleRawValue = item.cycleRawValue
        categoryRawValue = item.categoryRawValue
        nextRenewalDate = item.nextRenewalDate
        reminderEnabled = item.reminderEnabled
        note = item.note
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }

    func makeItem() -> RenewalItem {
        RenewalItem(
            id: id,
            name: name,
            amount: amount,
            currencyCode: currencyCode,
            cycle: BillingCycle(rawValue: cycleRawValue) ?? .monthly,
            category: RenewalCategory(rawValue: categoryRawValue) ?? .other,
            nextRenewalDate: nextRenewalDate,
            reminderEnabled: reminderEnabled,
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(to item: RenewalItem) {
        item.name = name
        item.amount = amount
        item.currencyCode = currencyCode
        item.cycleRawValue = cycleRawValue
        item.categoryRawValue = categoryRawValue
        item.nextRenewalDate = nextRenewalDate
        item.reminderEnabled = reminderEnabled
        item.note = note
        item.createdAt = createdAt
        item.updatedAt = updatedAt
    }
}

struct RenewalBackupPayload: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let items: [RenewalBackupRecord]

    init(items: [RenewalItem]) {
        formatVersion = 1
        exportedAt = .now
        self.items = items.map(RenewalBackupRecord.init)
    }
}

struct RenewalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let payload: RenewalBackupPayload

    init(items: [RenewalItem]) {
        payload = RenewalBackupPayload(items: items)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        payload = try Self.decoder.decode(RenewalBackupPayload.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encoder.encode(payload))
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
