// CustomersHomeView.swift
import SwiftUI

struct CustomersHomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Customers")
                    .font(.largeTitle).bold()
                Text("Customers page — more to come soon.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding()
        }
        .navigationTitle("Customers")
    }
}
