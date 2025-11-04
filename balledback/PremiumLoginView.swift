//
//  PremiumLoginView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct PremiumLoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var goToPremiumHome = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Premium Login")
                .font(.largeTitle)
                .bold()

            Text("Sign in to access premium features.")
                .foregroundStyle(.secondary)

            // Placeholder controls
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button {
                    goToPremiumHome = true
                } label: {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding()
        .navigationTitle("Premium Login")
        .navigationDestination(isPresented: $goToPremiumHome) {
            PremiumHomeContainerView()
        }
    }
}

#Preview {
    NavigationStack { PremiumLoginView() }
}
