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

    func update(id: UUID, with updated: Estimate, from source: EstimatorSource) {
        switch source {
        case .standard:
            if let idx = standardEstimates.firstIndex(where: { $0.id == id }) {
                // Preserve id and createdAt of existing item; update fields
                let preserved = standardEstimates[idx]
                standardEstimates[idx] = Estimate(
                    id: preserved.id,
                    createdAt: preserved.createdAt,
                    jobName: updated.jobName,
                    phoneNumber: updated.phoneNumber,
                    jobLocation: updated.jobLocation
                )
            }
        case .premium:
            if let idx = premiumEstimates.firstIndex(where: { $0.id == id }) {
                let preserved = premiumEstimates[idx]
                premiumEstimates[idx] = Estimate(
                    id: preserved.id,
                    createdAt: preserved.createdAt,
                    jobName: updated.jobName,
                    phoneNumber: updated.phoneNumber,
                    jobLocation: updated.jobLocation
                )
            }
        }
    }

    // MARK: - Undo helpers

    func insert(_ estimate: Estimate, at index: Int, for source: EstimatorSource) {
        switch source {
        case .standard:
            let safeIndex = max(0, min(index, standardEstimates.count))
            standardEstimates.insert(estimate, at: safeIndex)
        case .premium:
            let safeIndex = max(0, min(index, premiumEstimates.count))
            premiumEstimates.insert(estimate, at: safeIndex)
        }
    }

    func append(_ estimate: Estimate, for source: EstimatorSource) {
        switch source {
        case .standard:
            standardEstimates.append(estimate)
        case .premium:
            premiumEstimates.append(estimate)
        }
    }
}

