import SwiftData
import SwiftUI
import UIKit

private enum AppTab: Hashable {
    case dashboard
    case settings
}

struct RootView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var backgroundImageStore: BackgroundImageStore
    @EnvironmentObject private var exchangeRateStore: ExchangeRateStore
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query(sort: \RenewalItem.nextRenewalDate) private var items: [RenewalItem]

    @AppStorage("masterRemindersEnabled") private var masterRemindersEnabled = true
    @AppStorage("reminderLeadDays") private var reminderLeadDays = 3
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("reminderMinute") private var reminderMinute = 0
    @AppStorage("currencyConversionEnabled") private var currencyConversionEnabled = true
    @AppStorage("customBackgroundEnabled") private var customBackgroundEnabled = false
    @AppStorage("customBackgroundBlurRadius") private var customBackgroundBlurRadius = 16.0

    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        ZStack {
            AppBackgroundView(
                image: backgroundImageStore.image,
                isEnabled: customBackgroundEnabled,
                blurRadius: customBackgroundBlurRadius,
                reduceTransparency: reduceTransparency
            )

            TabView(selection: $selectedTab) {
                Tab("总览", systemImage: "chart.pie.fill", value: .dashboard) {
                    DashboardView()
                }

                Tab("设置", systemImage: "gearshape.fill", value: .settings) {
                    SettingsView()
                }
            }
            .sensoryFeedback(.selection, trigger: selectedTab)
        }
        .onChange(of: scenePhase, initial: true) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await synchronizeNotifications()
                if currencyConversionEnabled {
                    await exchangeRateStore.refreshIfNeeded()
                }
            }
        }
    }

    private func synchronizeNotifications() async {
        await notificationManager.synchronize(
            items: items,
            masterEnabled: masterRemindersEnabled,
            leadDays: reminderLeadDays,
            hour: reminderHour,
            minute: reminderMinute
        )
    }
}

private struct AppBackgroundView: View {
    let image: UIImage?
    let isEnabled: Bool
    let blurRadius: Double
    let reduceTransparency: Bool

    private var clampedBlurRadius: CGFloat {
        CGFloat(min(max(blurRadius, 0), 40))
    }

    private var readabilityOverlay: Color {
        Color(uiColor: .systemGroupedBackground)
            .opacity(reduceTransparency ? 1 : 0.68)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            if isEnabled, let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width + clampedBlurRadius * 4,
                            height: proxy.size.height + clampedBlurRadius * 4
                        )
                        .blur(radius: clampedBlurRadius, opaque: true)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

                readabilityOverlay
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
