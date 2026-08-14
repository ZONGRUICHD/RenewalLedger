import Foundation

struct RenewalOccurrence: Identifiable {
    let item: RenewalItem
    let date: Date

    var id: String { "\(item.id.uuidString)-\(date.timeIntervalSince1970)" }
}

struct CurrencyTotal: Identifiable {
    let currencyCode: String
    let amount: Double

    var id: String { currencyCode }

    var formatted: String {
        amount.formatted(.currency(code: currencyCode))
    }
}

enum RenewalProjection {
    static func interval(
        for period: SpendingPeriod,
        containing date: Date = .now,
        calendar: Calendar = .current
    ) -> DateInterval {
        switch period {
        case .month:
            return calendar.dateInterval(of: .month, for: date)
                ?? DateInterval(start: date, duration: 0)
        case .quarter:
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else {
                return DateInterval(start: date, duration: 0)
            }
            let firstMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: year, month: firstMonth, day: 1)) ?? date
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .year:
            return calendar.dateInterval(of: .year, for: date)
                ?? DateInterval(start: date, duration: 0)
        }
    }

    static func occurrences(
        for items: [RenewalItem],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [RenewalOccurrence] {
        items.flatMap { item in
            occurrences(for: item, in: interval, calendar: calendar)
        }
        .sorted { $0.date < $1.date }
    }

    static func totals(for occurrences: [RenewalOccurrence]) -> [CurrencyTotal] {
        let grouped = Dictionary(grouping: occurrences, by: { $0.item.currencyCode })
        return grouped.map { currencyCode, entries in
            CurrencyTotal(
                currencyCode: currencyCode,
                amount: entries.reduce(0) { $0 + $1.item.amount }
            )
        }
        .sorted { $0.currencyCode < $1.currencyCode }
    }

    static func money(_ amount: Double, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode))
    }

    private static func occurrences(
        for item: RenewalItem,
        in interval: DateInterval,
        calendar: Calendar
    ) -> [RenewalOccurrence] {
        guard item.amount >= 0, interval.duration > 0 else { return [] }

        var date = item.nextRenewalDate
        var safetyCounter = 0

        while date < interval.start && safetyCounter < 1_000 {
            let next = item.dateAfterOneCycle(from: date, calendar: calendar)
            guard next > date else { return [] }
            date = next
            safetyCounter += 1
        }

        var results: [RenewalOccurrence] = []
        while date < interval.end && safetyCounter < 1_000 {
            results.append(RenewalOccurrence(item: item, date: date))
            let next = item.dateAfterOneCycle(from: date, calendar: calendar)
            guard next > date else { break }
            date = next
            safetyCounter += 1
        }

        return results
    }
}
