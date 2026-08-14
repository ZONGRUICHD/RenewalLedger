import Foundation
import SwiftData
import SwiftUI
import UserNotifications

struct RenewalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager

    @AppStorage("masterRemindersEnabled") private var masterRemindersEnabled = true
    @AppStorage("reminderLeadDays") private var reminderLeadDays = 3
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("reminderMinute") private var reminderMinute = 0

    private let item: RenewalItem?

    @State private var name: String
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var cycle: BillingCycle
    @State private var category: RenewalCategory
    @State private var renewalDate: Date
    @State private var reminderEnabled: Bool
    @State private var note: String
    @State private var saveError: String?

    init(item: RenewalItem?) {
        self.item = item

        let defaults = UserDefaults.standard
        let defaultCurrency = defaults.string(forKey: "defaultCurrency") ?? CurrencyOption.cny.rawValue
        let defaultCycle = BillingCycle(
            rawValue: defaults.string(forKey: "defaultCycle") ?? ""
        ) ?? .monthly
        let defaultCategory = RenewalCategory(
            rawValue: defaults.string(forKey: "defaultCategory") ?? ""
        ) ?? .vps

        _name = State(initialValue: item?.name ?? "")
        _amountText = State(initialValue: item.map { String(format: "%.2f", $0.amount) } ?? "")
        _currencyCode = State(initialValue: item?.currencyCode ?? defaultCurrency)
        _cycle = State(initialValue: item?.cycle ?? defaultCycle)
        _category = State(initialValue: item?.category ?? defaultCategory)
        _renewalDate = State(initialValue: item?.nextRenewalDate ?? Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
        _reminderEnabled = State(initialValue: item?.reminderEnabled ?? true)
        _note = State(initialValue: item?.note ?? "")
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedAmount ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称，例如：香港 VPS", text: $name)
                        .textInputAutocapitalization(.never)

                    HStack {
                        TextField("金额", text: $amountText)
                            .keyboardType(.decimalPad)
                        Picker("币种", selection: $currencyCode) {
                            ForEach(CurrencyOption.allCases) { currency in
                                Text(currency.rawValue).tag(currency.rawValue)
                            }
                        }
                        .labelsHidden()
                    }

                    Picker("分类", selection: $category) {
                        ForEach(RenewalCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbolName)
                                .tag(category)
                        }
                    }
                }

                Section("续费规则") {
                    DatePicker(
                        "下次续费日",
                        selection: $renewalDate,
                        displayedComponents: .date
                    )

                    Picker("周期", selection: $cycle) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.title).tag(cycle)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("到期前提醒", isOn: $reminderEnabled)
                } footer: {
                    Text("当前设置为提前 \(reminderLeadDays) 天、\(String(format: "%02d:%02d", reminderHour, reminderMinute)) 提醒；可在设置页调整。")
                }

                Section("备注") {
                    TextField("机房、套餐、账号等可选信息", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(item == nil ? "添加续费" : "编辑续费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
            .alert(
                "无法保存",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "未知错误")
            }
        }
    }

    @MainActor
    private func save() async {
        guard let amount = parsedAmount, canSave else { return }

        let storedItem: RenewalItem
        if let item {
            item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            item.amount = amount
            item.currencyCode = currencyCode
            item.cycle = cycle
            item.category = category
            item.nextRenewalDate = Calendar.current.startOfDay(for: renewalDate)
            item.reminderEnabled = reminderEnabled
            item.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            item.updatedAt = .now
            storedItem = item
        } else {
            let newItem = RenewalItem(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                currencyCode: currencyCode,
                cycle: cycle,
                category: category,
                nextRenewalDate: renewalDate,
                reminderEnabled: reminderEnabled,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            modelContext.insert(newItem)
            storedItem = newItem
        }

        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            return
        }

        if masterRemindersEnabled, reminderEnabled {
            await notificationManager.refreshAuthorizationStatus()
            if notificationManager.authorizationStatus == .notDetermined {
                _ = await notificationManager.requestAuthorization()
            }
        }

        await notificationManager.schedule(
            item: storedItem,
            masterEnabled: masterRemindersEnabled,
            leadDays: reminderLeadDays,
            hour: reminderHour,
            minute: reminderMinute
        )
        dismiss()
    }
}
