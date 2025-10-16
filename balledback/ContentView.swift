//
//  ContentView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Premium") {
                // TODO: Handle Premium action
            }
            .buttonStyle(.borderedProminent)

            Button("Standard") {
                // TODO: Handle Standard action
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
