//
//  EstimatorMainView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

// Simple location manager to get a one-time region for biasing search.
final class OneShotLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var region: MKCoordinateRegion?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var didRequest = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        guard !didRequest else { return }
        didRequest = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            break
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        region = MKCoordinateRegion(center: loc.coordinate, span: span)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }
}

// Wrapper around MKLocalSearchCompleter for SwiftUI binding.
@MainActor
final class LocalSearchCompleterModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    init(region: MKCoordinateRegion? = nil) {
        self.completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        if let region {
            completer.region = region
        }
        completer.resultTypes = [.address]
    }

    func update(region: MKCoordinateRegion?) {
        if let region {
            completer.region = region
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

struct EstimatorMainView: View {
    // Breadcrumb: where the user came from
    let source: EstimatorSource
    // Optional existing estimate for edit mode
    let existingEstimate: Estimate?

    // Shared store
    @EnvironmentObject private var store: EstimatorStore
    @Environment(\.dismiss) private var dismiss

    @State private var jobName: String = ""
    @State private var phoneNumber: String = ""
    @State private var jobLocation: String = ""

    // Keep the initial values to detect unsaved changes
    @State private var initialJobName: String = ""
    @State private var initialPhoneNumber: String = ""
    @State private var initialJobLocation: String = ""

    // Location and search models
    @StateObject private var locationManager = OneShotLocationManager()
    @StateObject private var searchModel = LocalSearchCompleterModel()

    // Control suggestions visibility
    @State private var showSuggestions = false

    // Confirm discard/save draft
    @State private var showDiscardDialog = false

    // Enable Save if either job name OR job location has content
    private var canSave: Bool {
        let trimmedJobName = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = jobLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedJobName.isEmpty || !trimmedLocation.isEmpty
    }

    // Dirty check: any changes compared to initial values
    private var isDirty: Bool {
        let j = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = jobLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        let ij = initialJobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ip = initialPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let il = initialJobLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        return j != ij || p != ip || l != il
    }

    init(source: EstimatorSource, existingEstimate: Estimate? = nil) {
        self.source = source
        self.existingEstimate = existingEstimate
    }

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

                // Phone Number input (digits only)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone Number")
                        .font(.headline)

                    TextField("Enter phone number", text: $phoneNumber)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: phoneNumber) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                phoneNumber = filtered
                            }
                        }
                }

                // Job Location input with suggestions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Job Location")
                        .font(.headline)

                    TextField("Enter job location", text: $jobLocation, onEditingChanged: { isEditing in
                        showSuggestions = isEditing && !jobLocation.isEmpty
                    })
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: jobLocation) { _, newValue in
                        searchModel.query = newValue
                        showSuggestions = !newValue.isEmpty
                    }

                    if showSuggestions && !searchModel.results.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(searchModel.results, id: \.self) { item in
                                Button {
                                    let combined = item.title.isEmpty ? item.subtitle : "\(item.title) \(item.subtitle)"
                                    jobLocation = combined.trimmingCharacters(in: .whitespacesAndNewlines)
                                    showSuggestions = false
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .foregroundStyle(.primary)
                                            if !item.subtitle.isEmpty {
                                                Text(item.subtitle)
                                                    .foregroundStyle(.secondary)
                                                    .font(.subheadline)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)

                                if item != searchModel.results.last {
                                    Divider()
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(existingEstimate == nil ? "" : "Edit Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // we’ll provide our own back behavior

        .onAppear {
            // Prefill fields when editing and capture initial values
            if let estimate = existingEstimate {
                jobName = estimate.jobName
                phoneNumber = estimate.phoneNumber
                jobLocation = estimate.jobLocation
            }
            // Capture initial values for dirty checking
            initialJobName = jobName
            initialPhoneNumber = phoneNumber
            initialJobLocation = jobLocation

            // Request user location once to bias results
            locationManager.request()
        }
        .onReceive(locationManager.$region.compactMap { $0 }) { newRegion in
            searchModel.update(region: newRegion)
        }

        .toolbar {
            // Custom back button that asks to discard/save draft if dirty
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if isDirty {
                        showDiscardDialog = true
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                        Text("Back")
                    }
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Save button
                Button {
                    finalizeAndDismiss(save: true)
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(Color.blue)
                        )
                        .accessibilityLabel("Save estimate")
                }
                .disabled(!canSave)

                // Clear button
                Button {
                    jobName = ""
                    phoneNumber = ""
                    jobLocation = ""
                    searchModel.query = ""
                    showSuggestions = false
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

                // Settings menu (placeholder)
                Menu {
                    Button("Duplicate") {}
                    Button("More settings to come") {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .accessibilityLabel("Settings")
                }
            }
        }

        // Confirmation dialog for unsaved changes
        .confirmationDialog(
            "You have unsaved changes",
            isPresented: $showDiscardDialog,
            titleVisibility: .visible
        ) {
            Button("Save as Draft") {
                finalizeAndDismiss(save: true)
            }
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Would you like to save your changes as a draft or discard them?")
        }
    }

    // MARK: - Save helper

    private func finalizeAndDismiss(save: Bool) {
        // Stabilize before dismiss: stop completer updates and hide suggestions
        showSuggestions = false
        searchModel.query = ""

        guard save else {
            dismiss()
            return
        }

        let trimmed = Estimate(
            jobName: jobName.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            jobLocation: jobLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if let existing = existingEstimate {
            store.update(id: existing.id, with: trimmed, from: source)
        } else {
            store.add(trimmed, from: source)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        EstimatorMainView(source: .standard)
            .environmentObject(EstimatorStore())
    }
}
