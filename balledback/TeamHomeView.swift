// TeamHomeView.swift
import SwiftUI

struct TeamHomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Team")
                    .font(.largeTitle).bold()
                Text("Team page — more to come soon.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding()
        }
        .navigationTitle("Team")
        .navigationBarBackButtonHidden(true)
    }
}
