//
//  Estimate.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import Foundation

struct Estimate: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date

    var jobName: String
    var phoneNumber: String
    var jobLocation: String

    // Window category counts
    var groundCount: Int
    var secondCount: Int
    var threePlusCount: Int
    var basementCount: Int

    // Per-category prices
    var groundPrice: Double
    var secondPrice: Double
    var threePlusPrice: Double
    var basementPrice: Double

    // Per-category units
    var groundUnit: PricingUnit
    var secondUnit: PricingUnit
    var threePlusUnit: PricingUnit
    var basementUnit: PricingUnit

    // Advanced modifiers (optional to preserve compatibility)
    var groundModifiers: [AdvancedModifierItem]?
    var secondModifiers: [AdvancedModifierItem]?
    var threePlusModifiers: [AdvancedModifierItem]?
    var basementModifiers: [AdvancedModifierItem]?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        jobName: String,
        phoneNumber: String,
        jobLocation: String,
        groundCount: Int = 0,
        secondCount: Int = 0,
        threePlusCount: Int = 0,
        basementCount: Int = 0,
        groundPrice: Double = 0,
        secondPrice: Double = 0,
        threePlusPrice: Double = 0,
        basementPrice: Double = 0,
        groundUnit: PricingUnit = .window,
        secondUnit: PricingUnit = .window,
        threePlusUnit: PricingUnit = .window,
        basementUnit: PricingUnit = .window,
        groundModifiers: [AdvancedModifierItem]? = nil,
        secondModifiers: [AdvancedModifierItem]? = nil,
        threePlusModifiers: [AdvancedModifierItem]? = nil,
        basementModifiers: [AdvancedModifierItem]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.jobName = jobName
        self.phoneNumber = phoneNumber
        self.jobLocation = jobLocation

        self.groundCount = groundCount
        self.secondCount = secondCount
        self.threePlusCount = threePlusCount
        self.basementCount = basementCount

        self.groundPrice = groundPrice
        self.secondPrice = secondPrice
        self.threePlusPrice = threePlusPrice
        self.basementPrice = basementPrice

        self.groundUnit = groundUnit
        self.secondUnit = secondUnit
        self.threePlusUnit = threePlusUnit
        self.basementUnit = basementUnit

        self.groundModifiers = groundModifiers
        self.secondModifiers = secondModifiers
        self.threePlusModifiers = threePlusModifiers
        self.basementModifiers = basementModifiers
    }
}
