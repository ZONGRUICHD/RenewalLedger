import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            true
        default:
            false
        }
    }

    var statusTitle: String {
        switch authorizationStatus {
        case .notDetermined: "尚未请求"
        case .denied: "已关闭"
        case .authorized: "已允许"
        case .provisional: "暂时允许"
        case .ephemeral: "临时允许"
        @unknown default: "未知"
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func synchronize(
        items: [RenewalItem],
        masterEnabled: Bool,
        leadDays: Int,
        hour: Int,
        minute: Int
    ) async {
        center.removeAllPendingNotificationRequests()
        await refreshAuthorizationStatus()

        guard masterEnabled, isAuthorized else { return }

        let upcoming = items
            .filter(\.reminderEnabled)
            .sorted {
                nextDueDate(for: $0) < nextDueDate(for: $1)
            }

        // iOS keeps a bounded number of pending local notifications. Scheduling
        // only the next reminder for the nearest 64 items is predictable and safe.
        for item in upcoming.prefix(64) {
            await addRequest(
                item: item,
                leadDays: leadDays,
                hour: hour,
                minute: minute,
                // Activation sync never turns a missed trigger into a fresh
                // banner. That was the source of the launch-time repeat bug.
                allowLateReminder: false
            )
        }
    }

    func schedule(
        item: RenewalItem,
        masterEnabled: Bool,
        leadDays: Int,
        hour: Int,
        minute: Int
    ) async {
        let identifier = notificationIdentifier(for: item)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        await refreshAuthorizationStatus()

        guard masterEnabled, item.reminderEnabled, isAuthorized else { return }

        await addRequest(
            item: item,
            leadDays: leadDays,
            hour: hour,
            minute: minute,
            allowLateReminder: true
        )
    }

    func cancel(item: RenewalItem) {
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: item)]
        )
        defaults.removeObject(forKey: scheduledOccurrenceKey(for: item))
    }

    private func addRequest(
        item: RenewalItem,
        leadDays: Int,
        hour: Int,
        minute: Int,
        allowLateReminder: Bool
    ) async {
        let calendar = Calendar.current
        guard let schedule = nextReminderSchedule(
            for: item,
            leadDays: leadDays,
            hour: hour,
            minute: minute,
            allowLateReminder: allowLateReminder,
            calendar: calendar
        ) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "续费提醒 · \(item.name)"
        content.body = "将于 \(schedule.renewalDate.formatted(date: .abbreviated, time: .omitted))续费，金额 \(RenewalProjection.money(item.amount, currencyCode: item.currencyCode))。"
        content.sound = .default
        content.threadIdentifier = "renewal-reminders"
        content.interruptionLevel = .active
        content.userInfo = ["renewalID": item.id.uuidString]

        let trigger: UNNotificationTrigger
        if schedule.isLate {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 2,
                repeats: false
            )
        } else {
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: schedule.reminderDate
            )
            trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        }

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: item),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            recordScheduledOccurrence(
                for: item,
                renewalDate: schedule.renewalDate,
                calendar: calendar
            )
        } catch {
            // The authorization status and scheduling state are refreshed on
            // the next activation or settings change.
        }
    }

    private func nextReminderSchedule(
        for item: RenewalItem,
        leadDays: Int,
        hour: Int,
        minute: Int,
        allowLateReminder: Bool,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> (renewalDate: Date, reminderDate: Date, isLate: Bool)? {
        var renewalDate = nextDueDate(
            for: item,
            relativeTo: referenceDate,
            calendar: calendar
        )
        var safetyCounter = 0

        while safetyCounter < 1_000 {
            let dueDate = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: renewalDate
            ) ?? renewalDate
            let reminderDate = calendar.date(
                byAdding: .day,
                value: -max(0, leadDays),
                to: dueDate
            ) ?? dueDate

            if reminderDate > referenceDate {
                return (renewalDate, reminderDate, false)
            }

            let renewalDayEnd = calendar.date(
                bySettingHour: 23,
                minute: 59,
                second: 59,
                of: renewalDate
            ) ?? renewalDate
            let occurrenceToken = occurrenceToken(
                for: renewalDate,
                calendar: calendar
            )
            if allowLateReminder,
               referenceDate <= renewalDayEnd,
               !scheduledOccurrenceTokens(for: item).contains(occurrenceToken) {
                return (renewalDate, referenceDate.addingTimeInterval(2), true)
            }

            let nextRenewalDate = item.dateAfterOneCycle(
                from: renewalDate,
                calendar: calendar
            )
            guard nextRenewalDate > renewalDate else { return nil }
            renewalDate = nextRenewalDate
            safetyCounter += 1
        }

        return nil
    }

    private func notificationIdentifier(for item: RenewalItem) -> String {
        "renewal.\(item.id.uuidString)"
    }

    private func scheduledOccurrenceKey(for item: RenewalItem) -> String {
        "renewal.lastScheduledOccurrence.\(item.id.uuidString)"
    }

    private func occurrenceToken(for date: Date, calendar: Calendar) -> String {
        String(Int(calendar.startOfDay(for: date).timeIntervalSince1970))
    }

    private func scheduledOccurrenceTokens(for item: RenewalItem) -> [String] {
        defaults.stringArray(forKey: scheduledOccurrenceKey(for: item)) ?? []
    }

    private func recordScheduledOccurrence(
        for item: RenewalItem,
        renewalDate: Date,
        calendar: Calendar
    ) {
        let token = occurrenceToken(for: renewalDate, calendar: calendar)
        var tokens = scheduledOccurrenceTokens(for: item)
        tokens.removeAll { $0 == token }
        tokens.append(token)
        defaults.set(Array(tokens.suffix(8)), forKey: scheduledOccurrenceKey(for: item))
    }

    private func nextDueDate(
        for item: RenewalItem,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        var candidate = item.nextRenewalDate
        var safetyCounter = 0

        while (calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: candidate
        ) ?? candidate) < referenceDate && safetyCounter < 1_000 {
            let next = item.dateAfterOneCycle(from: candidate, calendar: calendar)
            guard next > candidate else { break }
            candidate = next
            safetyCounter += 1
        }
        return candidate
    }
}
