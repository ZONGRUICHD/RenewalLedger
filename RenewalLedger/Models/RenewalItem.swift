import Foundation
import SwiftData

@Model
final class RenewalItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Double
    var currencyCode: String
    var cycleRawValue: String
    var categoryRawValue: String
    var nextRenewalDate: Date
    var reminderEnabled: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        currencyCode: String,
        cycle: BillingCycle,
        category: RenewalCategory,
        nextRenewalDate: Date,
        reminderEnabled: Bool = true,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.cycleRawValue = cycle.rawValue
        self.categoryRawValue = category.rawValue
        self.nextRenewalDate = Calendar.current.startOfDay(for: nextRenewalDate)
        self.reminderEnabled = reminderEnabled
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension RenewalItem {
    var cycle: BillingCycle {
        get { BillingCycle(rawValue: cycleRawValue) ?? .monthly }
        set { cycleRawValue = newValue.rawValue }
    }

    var category: RenewalCategory {
        get { RenewalCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    func dateAfterOneCycle(from date: Date? = nil, calendar: Calendar = .current) -> Date {
        calendar.date(
            byAdding: .month,
            value: cycle.monthInterval,
            to: date ?? nextRenewalDate
        ) ?? nextRenewalDate
    }

    func advanceToNextOccurrence(after referenceDate: Date = .now, calendar: Calendar = .current) {
        var candidate = nextRenewalDate
        var safetyCounter = 0

        repeat {
            candidate = dateAfterOneCycle(from: candidate, calendar: calendar)
            safetyCounter += 1
        } while candidate <= referenceDate && safetyCounter < 1_000

        nextRenewalDate = candidate
        updatedAt = .now
    }
}
