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
                    // For now, immediately navigate to PremiumHomeView
                    goToPremiumHome = true
                } label: {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // You can enable validation by uncommenting:
                // .disabled(email.isEmpty || password.isEmpty)
            }
            .padding(.top, 8)
        }
        .padding()
        .navigationTitle("Premium Login")
        .navigationDestination(isPresented: $goToPremiumHome) {
            PremiumHomeView()
        }
    }
}

#Preview {
    NavigationStack { PremiumLoginView() }
}
