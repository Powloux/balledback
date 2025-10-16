//
//  balledbackApp.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

@main
struct balledbackApp: App {
    @StateObject private var estimatorStore = EstimatorStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(estimatorStore)
        }
    }
}
