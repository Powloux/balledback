//
//  PremiumHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct PremiumHomeView: View {
    @State private var goToEstimator = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 12) {
                Text("Premium Home")
                    .font(.largeTitle)
                    .bold()
                Text("This is a placeholder for the premium experience.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
        .navigationTitle("Premium")
        .navigationDestination(isPresented: $goToEstimator) {
            EstimatorMainView()
        }
    }
}

#Preview {
    NavigationStack { PremiumHomeView() }
}
