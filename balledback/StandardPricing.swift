import Foundation

struct StandardPricing: Codable, Equatable {
    var groundPrice: Double
    var secondPrice: Double
    var threePlusPrice: Double
    var basementPrice: Double

    var groundUnit: PricingUnit
    var secondUnit: PricingUnit
    var threePlusUnit: PricingUnit
    var basementUnit: PricingUnit

    static let `default` = StandardPricing(
        groundPrice: 0,
        secondPrice: 0,
        threePlusPrice: 0,
        basementPrice: 0,
        groundUnit: .window,
        secondUnit: .window,
        threePlusUnit: .window,
        basementUnit: .window
    )
}
