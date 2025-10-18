//
//  ContentView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                NavigationLink("Premium") {
                    PremiumLoginView()
                }
                .buttonStyle(.borderedProminent)

                NavigationLink("Standard") {
                    StandardHomeView()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Choose Plan")
        }
    }
}

#Preview {
    // Inject the required environment object so navigating in Canvas doesn't crash
    ContentView()
        .environmentObject(EstimatorStore())
}
