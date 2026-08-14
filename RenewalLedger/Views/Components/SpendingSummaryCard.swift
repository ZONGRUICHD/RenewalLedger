import SwiftUI

struct SpendingSummaryCard: View {
    let period: SpendingPeriod
    let occurrences: [RenewalOccurrence]
    let totals: [CurrencyTotal]
    let defaultCurrencyCode: String

    private var nextOccurrence: RenewalOccurrence? {
        occurrences.first { $0.date >= Calendar.current.startOfDay(for: .now) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(period.summaryTitle, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text("\(occurrences.count) 笔")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                if totals.isEmpty {
                    Text(RenewalProjection.money(0, currencyCode: defaultCurrencyCode))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                } else {
                    ForEach(totals) { total in
                        Text(total.formatted)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }

                if totals.count > 1 {
                    Text("不同币种分别统计，未使用不透明汇率换算")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let nextOccurrence {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下一笔 · \(nextOccurrence.item.name)")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(nextOccurrence.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(RenewalProjection.money(
                        nextOccurrence.item.amount,
                        currencyCode: nextOccurrence.item.currencyCode
                    ))
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Label("此周期暂无待续费项目", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
