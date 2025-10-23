//
//  PricingUnit.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import Foundation

enum PricingUnit: String, CaseIterable, Identifiable, Hashable {
    case window
    case pane

    var id: String { rawValue }
}
