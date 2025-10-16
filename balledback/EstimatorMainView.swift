//
//  EstimatorMainView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct EstimatorMainView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Estimator Main")
                .font(.largeTitle)
                .bold()
            Text("Placeholder for estimator features.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Estimator")
    }
}

#Preview {
    NavigationStack { EstimatorMainView() }
}
