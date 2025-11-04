//
//  EstimatorStore.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import Foundation
import Combine

@MainActor
final class EstimatorStore: ObservableObject {
    // Existing properties...

    @Published private(set) var standardEstimates: [Estimate] = []
    @Published private(set) var premiumEstimates: [Estimate] = []

    // NEW: Standard pricing defaults
    @Published var standardPricing: StandardPricing = .default {
        didSet { saveStandardPricing() }
    }

    private let pricingKey = "standardPricing"

    init() {
        loadStandardPricing()
    }

    private func loadStandardPricing() {
        if let data = UserDefaults.standard.data(forKey: pricingKey),
           let decoded = try? JSONDecoder().decode(StandardPricing.self, from: data) {
            standardPricing = decoded
        } else {
            standardPricing = .default
        }
    }

    private func saveStandardPricing() {
        if let data = try? JSONEncoder().encode(standardPricing) {
            UserDefaults.standard.set(data, forKey: pricingKey)
        }
    }

    // You may add a method to update, for convenience
    func updateStandardPricing(_ newPricing: StandardPricing) {
        standardPricing = newPricing // will auto-save
    }

    // ...existing methods unchanged...
    func add(_ estimate: Estimate, from source: EstimatorSource) { /* ... */ }
    func remove(id: UUID, from source: EstimatorSource) { /* ... */ }
    func clearAll(for source: EstimatorSource) { /* ... */ }
    func update(id: UUID, with updated: Estimate, from source: EstimatorSource) { /* ... */ }
    func insert(_ estimate: Estimate, at index: Int, for source: EstimatorSource) { /* ... */ }
    func append(_ estimate: Estimate, for source: EstimatorSource) { /* ... */ }
}
