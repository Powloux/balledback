import Foundation
import SwiftUI
import Combine

@MainActor
final class PremiumRouter: ObservableObject {
    // Routing state
    @Published var showEstimator: Bool = false
    @Published var editingEstimate: Estimate? = nil

    // Entry points
    func openNewEstimate() {
        editingEstimate = nil
        showEstimator = true
    }

    func openEdit(_ estimate: Estimate) {
        editingEstimate = estimate
        showEstimator = true
    }

    func dismissEstimator() {
        showEstimator = false
        editingEstimate = nil
    }
}
