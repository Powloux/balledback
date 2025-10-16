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

    @Published private(set) var standardEstimates: [Estimate] = []
    @Published private(set) var premiumEstimates: [Estimate] = []

    func add(_ estimate: Estimate, from source: EstimatorSource) {
        switch source {
        case .standard:
            standardEstimates.append(estimate)
        case .premium:
            premiumEstimates.append(estimate)
        }
    }

    func remove(id: UUID, from source: EstimatorSource) {
        switch source {
        case .standard:
            standardEstimates.removeAll { $0.id == id }
        case .premium:
            premiumEstimates.removeAll { $0.id == id }
        }
    }

    func clearAll(for source: EstimatorSource) {
        switch source {
        case .standard:
            standardEstimates.removeAll()
        case .premium:
            premiumEstimates.removeAll()
        }
    }
}
