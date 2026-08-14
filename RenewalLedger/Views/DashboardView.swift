import SwiftData
import SwiftUI

private struct RenewalEditorRoute: Identifiable {
    let id = UUID()
    let item: RenewalItem?
}

struct DashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query(sort: \RenewalItem.nextRenewalDate) private var items: [RenewalItem]

    @AppStorage("defaultCurrency") private var defaultCurrency = CurrencyOption.cny.rawValue
    @AppStorage("masterRemindersEnabled") private var masterRemindersEnabled = true
    @AppStorage("reminderLeadDays") private var reminderLeadDays = 3
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("reminderMinute") private var reminderMinute = 0

    @State private var selectedPeriod: SpendingPeriod = .month
    @State private var searchText = ""
    @State private var editorRoute: RenewalEditorRoute?
    @State private var pendingDelete: RenewalItem?
    @State private var renewalFeedback = 0

    private var projectedOccurrences: [RenewalOccurrence] {
        RenewalProjection.occurrences(
            for: items,
            in: RenewalProjection.interval(for: selectedPeriod)
        )
    }

    private var filteredItems: [RenewalItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return items
        }
        return items.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.category.title.localizedStandardContains(searchText)
                || $0.note.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("统计周期", selection: $selectedPeriod) {
                        ForEach(SpendingPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)

                    SpendingSummaryCard(
                        period: selectedPeriod,
                        occurrences: projectedOccurrences,
                        totals: RenewalProjection.totals(for: projectedOccurrences),
                        defaultCurrencyCode: defaultCurrency
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                }

                Section {
                    if filteredItems.isEmpty {
                        ContentUnavailableView {
                            Label(
                                searchText.isEmpty ? "还没有续费项目" : "没有搜索结果",
                                systemImage: searchText.isEmpty ? "calendar.badge.plus" : "magnifyingglass"
                            )
                        } description: {
                            Text(searchText.isEmpty ? "点右上角的加号，记下第一项 VPS 或会员续费。" : "尝试搜索其他名称或分类。")
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredItems) { item in
                            Button {
                                editorRoute = RenewalEditorRoute(item: item)
                            } label: {
                                RenewalRow(item: item, leadDays: reminderLeadDays)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    markRenewed(item)
                                } label: {
                                    Label("已续费", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = item
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }

                                Button {
                                    editorRoute = RenewalEditorRoute(item: item)
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("续费项目")
                        Spacer()
                        Text("\(items.count)")
                    }
                } footer: {
                    if !items.isEmpty {
                        Text("向右轻扫项目可标记已续费，并自动推进到下一个账期。")
                    }
                }
            }
            .navigationTitle("续费簿")
            .searchable(text: $searchText, prompt: "搜索 VPS、会员或备注")
            .sensoryFeedback(.selection, trigger: selectedPeriod)
            .sensoryFeedback(.success, trigger: renewalFeedback)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorRoute = RenewalEditorRoute(item: nil)
                    } label: {
                        Label("添加续费", systemImage: "plus")
                    }
                    .accessibilityHint("添加一个新的续费项目")
                }
            }
            .sheet(item: $editorRoute) { route in
                RenewalEditorView(item: route.item)
            }
            .confirmationDialog(
                "删除“\(pendingDelete?.name ?? "这个项目")”？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    guard let item = pendingDelete else { return }
                    delete(item)
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text("此操作会同时取消该项目尚未发送的提醒。")
            }
        }
    }

    private func markRenewed(_ item: RenewalItem) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.2)) {
            item.advanceToNextOccurrence()
            renewalFeedback += 1
            try? modelContext.save()
        }
        Task {
            await notificationManager.schedule(
                item: item,
                masterEnabled: masterRemindersEnabled,
                leadDays: reminderLeadDays,
                hour: reminderHour,
                minute: reminderMinute
            )
        }
    }

    private func delete(_ item: RenewalItem) {
        notificationManager.cancel(item: item)
        withAnimation(reduceMotion ? nil : .spring(duration: 0.46, bounce: 0.12)) {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }
}
