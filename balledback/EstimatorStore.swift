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

    // NEW: scheduled jobs (read-only for now; no UI to add/edit yet)
    @Published var scheduledJobs: [ScheduledJob] = []

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

    // MARK: - Estimates routing (in-memory)

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
            if let idx = standardEstimates.firstIndex(where: { $0.id == id }) {
                standardEstimates.remove(at: idx)
            }
        case .premium:
            if let idx = premiumEstimates.firstIndex(where: { $0.id == id }) {
                premiumEstimates.remove(at: idx)
            }
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
                standardEstimates[idx] = updated
            }
        case .premium:
            if let idx = premiumEstimates.firstIndex(where: { $0.id == id }) {
                premiumEstimates[idx] = updated
            }
        }
    }

    func insert(_ estimate: Estimate, at index: Int, for source: EstimatorSource) {
        switch source {
        case .standard:
            let i = max(0, min(index, standardEstimates.count))
            standardEstimates.insert(estimate, at: i)
        case .premium:
            let i = max(0, min(index, premiumEstimates.count))
            premiumEstimates.insert(estimate, at: i)
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

    // MARK: - Scheduling helpers (read-only use for now)

    // Return scheduled jobs that overlap the given interval and occur on the given day,
    // sorted by start time ascending.
    func jobs(on day: Date, in interval: DateInterval) -> [ScheduledJob] {
        let cal = Calendar.current
        return scheduledJobs
            .filter { job in
                // Same calendar day as 'day'
                cal.isDate(job.startDate, inSameDayAs: day) &&
                // Overlaps the interval [start, end]
                job.endDate > interval.start && job.startDate < interval.end
            }
            .sorted { $0.startDate < $1.startDate }
    }
}
