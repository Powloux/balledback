//
//  StandardHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct StandardHomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Standard Home")
                .font(.largeTitle)
                .bold()
            Text("This is a placeholder for the standard experience.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Standard")
    }
}

#Preview {
    NavigationStack { StandardHomeView() }
}
