// QuotesHomeView.swift
import SwiftUI

struct QuotesHomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Quotes")
                    .font(.largeTitle).bold()
                Text("Quotes page — more to come soon.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding()
        }
        .navigationTitle("Quotes")
    }
}
