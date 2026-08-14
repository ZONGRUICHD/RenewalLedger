import SwiftData
import SwiftUI

private enum AppTab: Hashable {
    case dashboard
    case settings
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query(sort: \RenewalItem.nextRenewalDate) private var items: [RenewalItem]

    @AppStorage("masterRemindersEnabled") private var masterRemindersEnabled = true
    @AppStorage("reminderLeadDays") private var reminderLeadDays = 3
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("reminderMinute") private var reminderMinute = 0

    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("总览", systemImage: "chart.pie.fill", value: .dashboard) {
                DashboardView()
            }

            Tab("设置", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .task {
            await synchronizeNotifications()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await synchronizeNotifications() }
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
