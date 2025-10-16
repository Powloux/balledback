//
//  PremiumHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct PremiumHomeView: View {
    
    
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Premium Home")
                .font(.largeTitle)
                .bold()
            Text("This is a placeholder for the premium experience.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Premium")
    }
}

#Preview {
    NavigationStack { PremiumHomeView() }
}
