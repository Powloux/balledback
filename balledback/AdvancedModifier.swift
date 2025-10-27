//
//  AdvancedModifier.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import Foundation

enum AdvancedModifierMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case price
    case multiplier

    var id: String { rawValue }
}

struct AdvancedModifierItem: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var isCustom: Bool
    var mode: AdvancedModifierMode
    var priceValue: Double
    var multiplierValue: Double

    init(
        id: UUID = UUID(),
        name: String,
        isCustom: Bool = false,
        mode: AdvancedModifierMode = .price,
        priceValue: Double = 0,
        multiplierValue: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.isCustom = isCustom
        self.mode = mode
        self.priceValue = priceValue
        self.multiplierValue = multiplierValue
    }
}

// Add this extension
extension AdvancedModifierMode {
    var title: String {
        switch self {
        case .price:
            return "Price"
        case .multiplier:
            return "Multiplier"
        }
    }
}
