import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var backgroundImageStore: BackgroundImageStore
    @EnvironmentObject private var exchangeRateStore: ExchangeRateStore
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query(sort: \RenewalItem.nextRenewalDate) private var items: [RenewalItem]

    @AppStorage("masterRemindersEnabled") private var masterRemindersEnabled = true
    @AppStorage("reminderLeadDays") private var reminderLeadDays = 3
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("reminderMinute") private var reminderMinute = 0
    @AppStorage("defaultCurrency") private var defaultCurrency = CurrencyOption.cny.rawValue
    @AppStorage("currencyConversionEnabled") private var currencyConversionEnabled = true
    @AppStorage("summaryCurrencyCode") private var summaryCurrencyCode = CurrencyOption.cny.rawValue
    @AppStorage("defaultCycle") private var defaultCycle = BillingCycle.monthly.rawValue
    @AppStorage("defaultCategory") private var defaultCategory = RenewalCategory.vps.rawValue
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("customBackgroundEnabled") private var customBackgroundEnabled = false
    @AppStorage("customBackgroundBlurRadius") private var customBackgroundBlurRadius = 16.0

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showResetConfirmation = false
    @State private var operationError: String?
    @State private var operationMessage: String?
    @State private var selectedBackgroundPhoto: PhotosPickerItem?
    @State private var backgroundImportTask: Task<Void, Never>?
    @State private var backgroundImportToken: UUID?
    @State private var isImportingBackground = false

    private var reminderTime: Binding<Date> {
        Binding {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: .now)
            components.hour = reminderHour
            components.minute = reminderMinute
            return calendar.date(from: components) ?? .now
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 9
            reminderMinute = components.minute ?? 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                currencyConversionSection
                defaultsSection
                appearanceSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("设置")
            .sensoryFeedback(.selection, trigger: appearance)
            .task {
                await notificationManager.refreshAuthorizationStatus()
                if currencyConversionEnabled {
                    await exchangeRateStore.refreshIfNeeded()
                }
            }
            .onChange(of: reminderLeadDays) { _, _ in synchronizeNotifications() }
            .onChange(of: reminderHour) { _, _ in synchronizeNotifications() }
            .onChange(of: reminderMinute) { _, _ in synchronizeNotifications() }
            .onChange(of: currencyConversionEnabled) { _, enabled in
                guard enabled else { return }
                Task { await exchangeRateStore.refreshIfNeeded() }
            }
            .onChange(of: selectedBackgroundPhoto) { _, newItem in
                importBackground(from: newItem)
            }
            .fileExporter(
                isPresented: $isExporting,
                document: RenewalBackupDocument(items: items),
                contentType: .json,
                defaultFilename: "RenewalLedger-Backup"
            ) { result in
                if case .failure(let error) = result {
                    operationError = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importBackup(from: url)
                case .failure(let error):
                    operationError = error.localizedDescription
                }
            }
            .confirmationDialog(
                "清除全部数据？",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除 \(items.count) 个项目", role: .destructive) {
                    resetAllData()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作无法撤销，建议先导出 JSON 备份。")
            }
            .alert(
                "操作未完成",
                isPresented: Binding(
                    get: { operationError != nil },
                    set: { if !$0 { operationError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(operationError ?? "未知错误")
            }
            .alert(
                "完成",
                isPresented: Binding(
                    get: { operationMessage != nil },
                    set: { if !$0 { operationMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(operationMessage ?? "")
            }
        }
    }

    private var currencyConversionSection: some View {
        Section {
            Toggle("统一换算总支出", isOn: $currencyConversionEnabled)

            if currencyConversionEnabled {
                Picker("统计币种", selection: $summaryCurrencyCode) {
                    ForEach(CurrencyOption.allCases) { currency in
                        Text(currency.title).tag(currency.rawValue)
                    }
                }

                LabeledContent("参考汇率", value: exchangeRateStore.statusTitle)

                Button {
                    Task { await exchangeRateStore.refreshIfNeeded(force: true) }
                } label: {
                    if exchangeRateStore.isRefreshing {
                        Label("正在更新汇率", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("立即更新汇率", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(exchangeRateStore.isRefreshing)
            }
        } header: {
            Text("总支出与汇率")
        } footer: {
            Text("开启后按欧洲央行每日参考汇率换算。本应用只请求公开汇率，不会上传续费项目、金额或备注；断网时使用上次成功缓存。")
        }
    }

    private var notificationSection: some View {
        Section {
            LabeledContent("系统通知", value: notificationManager.statusTitle)

            switch notificationManager.authorizationStatus {
            case .notDetermined:
                Button {
                    Task {
                        let granted = await notificationManager.requestAuthorization()
                        if granted {
                            await synchronizeNotificationsNow()
                        }
                    }
                } label: {
                    Label("允许通知", systemImage: "bell.badge")
                }
            case .denied:
                Button {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                } label: {
                    Label("前往系统设置", systemImage: "arrow.up.forward.app")
                }
            default:
                EmptyView()
            }

            Toggle("续费提醒", isOn: $masterRemindersEnabled)
                .onChange(of: masterRemindersEnabled) { _, enabled in
                    Task {
                        if enabled {
                            await notificationManager.refreshAuthorizationStatus()
                            if notificationManager.authorizationStatus == .notDetermined {
                                let granted = await notificationManager.requestAuthorization()
                                if !granted {
                                    masterRemindersEnabled = false
                                    return
                                }
                            }
                        }
                        await synchronizeNotificationsNow()
                    }
                }

            Stepper(value: $reminderLeadDays, in: 1...30) {
                LabeledContent("提前提醒", value: "\(reminderLeadDays) 天")
            }

            DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
        } header: {
            Text("提醒")
        }
    }

    private var defaultsSection: some View {
        Section("添加项目时的默认值") {
            Picker("币种", selection: $defaultCurrency) {
                ForEach(CurrencyOption.allCases) { currency in
                    Text(currency.title).tag(currency.rawValue)
                }
            }

            Picker("周期", selection: $defaultCycle) {
                ForEach(BillingCycle.allCases) { cycle in
                    Text(cycle.title).tag(cycle.rawValue)
                }
            }

            Picker("分类", selection: $defaultCategory) {
                ForEach(RenewalCategory.allCases) { category in
                    Label(category.title, systemImage: category.symbolName)
                        .tag(category.rawValue)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("显示模式", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }

            if let image = backgroundImageStore.image {
                BackgroundPreview(
                    image: image,
                    blurRadius: customBackgroundBlurRadius
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                Toggle("使用自定义背景", isOn: $customBackgroundEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(
                        "背景模糊",
                        value: "\(Int(clampedBackgroundBlurRadius))"
                    )
                    Slider(
                        value: $customBackgroundBlurRadius,
                        in: 0...40,
                        step: 1
                    )
                    .accessibilityLabel("背景模糊程度")
                    .accessibilityValue("\(Int(clampedBackgroundBlurRadius)) 级")
                }
            }

            PhotosPicker(
                selection: $selectedBackgroundPhoto,
                matching: .images
            ) {
                if isImportingBackground {
                    Label("正在处理图片", systemImage: "photo.badge.arrow.down")
                } else {
                    Label(
                        backgroundImageStore.hasImage ? "更换背景图片" : "选择背景图片",
                        systemImage: "photo.on.rectangle"
                    )
                }
            }
            .disabled(isImportingBackground)

            if backgroundImageStore.hasImage {
                Button(role: .destructive) {
                    removeBackgroundImage()
                } label: {
                    Label("移除背景图片", systemImage: "trash")
                }
            }
        } header: {
            Text("外观")
        } footer: {
            Text("背景图片经过缩放后仅保存在本机，不会包含在 JSON 备份中。关闭开关会隐藏图片，但不会删除。")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                isExporting = true
            } label: {
                Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
            }
            .disabled(items.isEmpty)

            Button {
                isImporting = true
            } label: {
                Label("导入 JSON 备份", systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("清除全部数据", systemImage: "trash")
            }
            .disabled(items.isEmpty)
        } header: {
            Text("数据")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("应用", value: "续费簿")
            LabeledContent("版本", value: versionText)
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var clampedBackgroundBlurRadius: Double {
        min(max(customBackgroundBlurRadius, 0), 40)
    }

    private func synchronizeNotifications() {
        Task { await synchronizeNotificationsNow() }
    }

    private func importBackground(from item: PhotosPickerItem?) {
        backgroundImportTask?.cancel()
        guard let item else { return }

        let token = UUID()
        backgroundImportToken = token
        isImportingBackground = true
        backgroundImportTask = Task {
            defer {
                if backgroundImportToken == token {
                    backgroundImportToken = nil
                    isImportingBackground = false
                    selectedBackgroundPhoto = nil
                }
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw BackgroundImageError.invalidImage
                }
                try Task.checkCancellation()
                try await backgroundImageStore.importImage(from: data)
                customBackgroundEnabled = true
            } catch is CancellationError {
                return
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func removeBackgroundImage() {
        backgroundImportTask?.cancel()
        backgroundImportToken = nil
        isImportingBackground = false
        do {
            try backgroundImageStore.removeImage()
            customBackgroundEnabled = false
        } catch {
            operationError = error.localizedDescription
        }
    }

    @MainActor
    private func synchronizeNotificationsNow() async {
        await notificationManager.synchronize(
            items: items,
            masterEnabled: masterRemindersEnabled,
            leadDays: reminderLeadDays,
            hour: reminderHour,
            minute: reminderMinute
        )
    }

    private func importBackup(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try RenewalBackupDocument.decoder.decode(
                RenewalBackupPayload.self,
                from: data
            )
            guard payload.formatVersion == 1 else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            var existingByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            for record in payload.items {
                if let existing = existingByID[record.id] {
                    record.apply(to: existing)
                } else {
                    let newItem = record.makeItem()
                    modelContext.insert(newItem)
                    existingByID[record.id] = newItem
                }
            }
            try modelContext.save()

            let mergedItems = Array(existingByID.values)
            Task {
                await notificationManager.synchronize(
                    items: mergedItems,
                    masterEnabled: masterRemindersEnabled,
                    leadDays: reminderLeadDays,
                    hour: reminderHour,
                    minute: reminderMinute
                )
            }
            operationMessage = "已导入 \(payload.items.count) 个项目；同 ID 项目已更新。"
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func resetAllData() {
        for item in items {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
            Task {
                await notificationManager.synchronize(
                    items: [],
                    masterEnabled: masterRemindersEnabled,
                    leadDays: reminderLeadDays,
                    hour: reminderHour,
                    minute: reminderMinute
                )
            }
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private struct BackgroundPreview: View {
    let image: UIImage
    let blurRadius: Double

    var body: some View {
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
                .overlay(Color.black.opacity(0.12))
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("当前自定义背景预览")
    }

    private var clampedBlurRadius: CGFloat {
        CGFloat(min(max(blurRadius, 0), 40))
    }
}
