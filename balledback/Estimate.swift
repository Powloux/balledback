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

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        jobName: String,
        phoneNumber: String,
        jobLocation: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.jobName = jobName
        self.phoneNumber = phoneNumber
        self.jobLocation = jobLocation
    }
}
