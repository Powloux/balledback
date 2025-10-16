//
//  EstimatorMainView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct EstimatorMainView: View {
    @State private var jobName: String = ""
    @State private var phoneNumber: String = ""
    @State private var jobLocation: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Job Name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Job Name")
                        .font(.headline)

                    TextField("Enter job name", text: $jobName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                }

                // Phone Number input (same style as Job Name)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone Number")
                        .font(.headline)

                    TextField("Enter phone number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                }

                // Job Location input (same style)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Job Location")
                        .font(.headline)

                    TextField("Enter job location", text: $jobLocation)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Red Clear pill button (now left of the settings icon)
                Button {
                    // Clear all estimator inputs
                    jobName = ""
                    phoneNumber = ""
                    jobLocation = ""
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(Color.red)
                        )
                        .accessibilityLabel("Clear all fields")
                }

                // Settings menu button (circle with 3 horizontal dots) — far right
                Menu {
                    Button("Duplicate") {
                        // Placeholder: duplicate current estimator data
                    }
                    Button("More settings to come") {
                        // Placeholder for future settings
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .accessibilityLabel("Settings")
                }
            }
        }
    }
}

#Preview {
    NavigationStack { EstimatorMainView() }
}
