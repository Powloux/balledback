// MapHomeView.swift
import SwiftUI

struct MapHomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Map")
                    .font(.largeTitle).bold()
                Text("Map page — more to come soon.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding()
        }
        .navigationTitle("Map")
    }
}
