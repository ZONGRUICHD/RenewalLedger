import SwiftUI

struct RenewalRow: View {
    let item: RenewalItem
    let leadDays: Int

    private var daysUntilRenewal: Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: item.nextRenewalDate)
        ).day ?? 0
    }

    private var statusText: String {
        switch daysUntilRenewal {
        case ..<0: "已过期 \(-daysUntilRenewal) 天"
        case 0: "今天到期"
        case 1: "明天到期"
        default: "\(daysUntilRenewal) 天后"
        }
    }

    private var statusColor: Color {
        if daysUntilRenewal < 0 { return .red }
        if daysUntilRenewal <= leadDays { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.category.tint)
                .frame(width: 42, height: 42)
                .background(item.category.tint.opacity(0.14), in: Circle())
                .symbolEffect(.bounce, value: item.nextRenewalDate)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if item.reminderEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("已开启提醒")
                    }
                }
                Text("\(item.cycle.shortTitle) · \(item.nextRenewalDate.formatted(date: .numeric, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(RenewalProjection.money(item.amount, currencyCode: item.currencyCode))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(statusText)
                    .font(.caption.weight(daysUntilRenewal <= leadDays ? .semibold : .regular))
                    .foregroundStyle(statusColor)
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点编辑，向右轻扫可标记已续费")
    }
}
