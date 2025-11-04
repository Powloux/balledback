// PremiumSection.swift
import Foundation

enum PremiumSection: CaseIterable, Identifiable {
    case dashboard
    case quotes
    case team
    case map
    case customers

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .quotes: return "Quotes"
        case .team: return "Team"
        case .map: return "Map"
        case .customers: return "Customers"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house.fill"
        case .quotes: return "long.text.page.and.pencil.fill"
        case .team: return "person.2.wave.2.fill"
        case .map: return "map.fill"
        case .customers: return "person.3.fill"
        }
    }
}
