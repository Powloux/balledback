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

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        jobName: String,
        phoneNumber: String,
        jobLocation: String,
        groundCount: Int = 0,
        secondCount: Int = 0,
        threePlusCount: Int = 0,
        basementCount: Int = 0
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
    }
}
