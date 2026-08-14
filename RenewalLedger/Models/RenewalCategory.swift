import SwiftUI

enum RenewalCategory: String, CaseIterable, Codable, Identifiable {
    case vps
    case membership
    case domain
    case software
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vps: "VPS / 服务器"
        case .membership: "会员订阅"
        case .domain: "域名"
        case .software: "软件服务"
        case .other: "其他"
        }
    }

    var symbolName: String {
        switch self {
        case .vps: "server.rack"
        case .membership: "person.crop.circle.badge.checkmark"
        case .domain: "globe"
        case .software: "app.badge.checkmark"
        case .other: "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .vps: .blue
        case .membership: .purple
        case .domain: .teal
        case .software: .orange
        case .other: .gray
        }
    }
}
