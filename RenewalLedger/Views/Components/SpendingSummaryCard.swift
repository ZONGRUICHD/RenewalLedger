import Foundation
import SwiftUI

struct SpendingSummaryCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let period: SpendingPeriod
    let occurrences: [RenewalOccurrence]
    let totals: [CurrencyTotal]
    let defaultCurrencyCode: String

    @State private var pulseScale: CGFloat = 1
    @State private var shinePosition: CGFloat = -0.5

    private var nextOccurrence: RenewalOccurrence? {
        occurrences.first { $0.date >= Calendar.current.startOfDay(for: .now) }
    }

    private var totalsAnimationKey: String {
        totals
            .map { "\($0.currencyCode):\($0.amount)" }
            .joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: period)

                ZStack(alignment: .leading) {
                    Text(period.summaryTitle)
                        .id(period)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
                .font(.headline)

                Spacer()
                Text("\(occurrences.count) 笔")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .animation(
                reduceMotion ? nil : .spring(duration: 0.46, bounce: 0.16),
                value: period
            )
            .animation(
                reduceMotion ? nil : .spring(duration: 0.44, bounce: 0.12),
                value: occurrences.count
            )

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
            .animation(
                reduceMotion ? nil : .spring(duration: 0.56, bounce: 0.18),
                value: totalsAnimationKey
            )

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
                    .contentTransition(.numericText())
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
        .overlay {
            if !reduceMotion {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.2),
                            Color.accentColor.opacity(0.08),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geometry.size.width * 0.34)
                    .rotationEffect(.degrees(12))
                    .offset(x: geometry.size.width * shinePosition)
                    .blendMode(.plusLighter)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .scaleEffect(pulseScale)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.48, bounce: 0.18),
            value: nextOccurrence?.id
        )
        .onChange(of: period) { _, _ in
            guard !reduceMotion else { return }

            withAnimation(.easeOut(duration: 0.08)) {
                pulseScale = 0.982
            }
            shinePosition = -0.5
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.62)) {
                    shinePosition = 1.2
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(duration: 0.52, bounce: 0.24)) {
                    pulseScale = 1
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
