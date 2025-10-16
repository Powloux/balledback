//
//  StandardHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct StandardHomeView: View {
    @State private var goToEstimator = false
    @EnvironmentObject private var store: EstimatorStore

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Scrollable content area; add your future content here
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Display saved standard estimates
                    if !store.standardEstimates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved Estimates")
                                .font(.headline)
                            ForEach(store.standardEstimates) { estimate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(estimate.jobName).font(.subheadline.weight(.semibold))
                                    if !estimate.jobLocation.isEmpty {
                                        Text(estimate.jobLocation).foregroundStyle(.secondary)
                                    }
                                    if !estimate.phoneNumber.isEmpty {
                                        Text(estimate.phoneNumber).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                            }
                        }
                    }
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
            EstimatorMainView(source: .standard)
        }
    }
}

#Preview {
    NavigationStack { StandardHomeView().environmentObject(EstimatorStore()) }
}
