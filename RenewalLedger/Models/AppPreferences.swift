import SwiftUI

enum SpendingPeriod: String, CaseIterable, Identifiable {
    case month
    case quarter
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "本月"
        case .quarter: "本季度"
        case .year: "今年"
        }
    }

    var summaryTitle: String { "\(title)预计支出" }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CurrencyOption: String, CaseIterable, Identifiable {
    case cny = "CNY"
    case usd = "USD"
    case hkd = "HKD"
    case jpy = "JPY"
    case eur = "EUR"
    case gbp = "GBP"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cny: "人民币（CNY）"
        case .usd: "美元（USD）"
        case .hkd: "港币（HKD）"
        case .jpy: "日元（JPY）"
        case .eur: "欧元（EUR）"
        case .gbp: "英镑（GBP）"
        }
    }
}
