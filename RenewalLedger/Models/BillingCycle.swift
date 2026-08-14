import Foundation

enum BillingCycle: String, CaseIterable, Codable, Identifiable {
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: "每月"
        case .quarterly: "每季度"
        case .yearly: "每年"
        }
    }

    var shortTitle: String {
        switch self {
        case .monthly: "月付"
        case .quarterly: "季付"
        case .yearly: "年付"
        }
    }

    var monthInterval: Int {
        switch self {
        case .monthly: 1
        case .quarterly: 3
        case .yearly: 12
        }
    }
}
