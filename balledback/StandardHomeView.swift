//
//  StandardHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct StandardHomeView: View {
    @State private var goToEstimator = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Scrollable content area; add your future content here
            ScrollView {
                // Placeholder for future content; keeps area scrollable
                VStack(alignment: .leading, spacing: 16) {
                    // Add sections, lists, etc. here as you build features
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            // Floating action button pinned to bottom-right
            Button {
                goToEstimator = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.blue))
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            }
            .padding(20)
            .accessibilityLabel("Add")
        }
        .navigationTitle("Standard")
        .navigationDestination(isPresented: $goToEstimator) {
            EstimatorMainView()
        }
    }
}

#Preview {
    NavigationStack { StandardHomeView() }
}
