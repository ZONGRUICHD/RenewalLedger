import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

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
                minute: minute
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
            minute: minute
        )
    }

    func cancel(item: RenewalItem) {
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: item)]
        )
    }

    private func addRequest(
        item: RenewalItem,
        leadDays: Int,
        hour: Int,
        minute: Int
    ) async {

        let calendar = Calendar.current
        let upcomingRenewalDate = nextDueDate(for: item, calendar: calendar)
        let dueDate = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: upcomingRenewalDate
        ) ?? upcomingRenewalDate

        let reminderDate = calendar.date(
            byAdding: .day,
            value: -max(0, leadDays),
            to: dueDate
        ) ?? dueDate

        let content = UNMutableNotificationContent()
        content.title = "续费提醒 · \(item.name)"
        content.body = "将于 \(upcomingRenewalDate.formatted(date: .abbreviated, time: .omitted))续费，金额 \(RenewalProjection.money(item.amount, currencyCode: item.currencyCode))。"
        content.sound = .default
        content.threadIdentifier = "renewal-reminders"
        content.interruptionLevel = .active
        content.userInfo = ["renewalID": item.id.uuidString]

        let trigger: UNNotificationTrigger
        if reminderDate <= .now {
            // If the user adds an item less than leadDays before it is due,
            // deliver a useful reminder immediately instead of silently missing it.
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        } else {
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminderDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    private func notificationIdentifier(for item: RenewalItem) -> String {
        "renewal.\(item.id.uuidString)"
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
