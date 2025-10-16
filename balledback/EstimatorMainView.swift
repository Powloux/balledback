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
            // Keep going without location; region will remain nil
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
        // Create a modest span to bias local results
        let span = MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        region = MKCoordinateRegion(center: loc.coordinate, span: span)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // If location fails, we simply won't bias the search region.
        // You could log or handle the error as needed.
    }
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
        // Prioritize addresses
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
        // Clear results on error; you could also show an error message if desired.
        results = []
    }
}

struct EstimatorMainView: View {
    @State private var jobName: String = ""
    @State private var phoneNumber: String = ""
    @State private var jobLocation: String = ""

    // Location and search models
    @StateObject private var locationManager = OneShotLocationManager()
    @StateObject private var searchModel = LocalSearchCompleterModel()

    // Control suggestions visibility
    @State private var showSuggestions = false

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
                        // Suggestions list
                        VStack(spacing: 0) {
                            ForEach(searchModel.results, id: \.self) { item in
                                Button {
                                    // Fill the text field with a readable combination
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

                                // Divider between rows
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
        // Keep the nav bar for toolbar items, but hide the title text
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)

        .onAppear {
            // Request user location once to bias results
            locationManager.request()
        }
        // Observe region updates without requiring Equatable conformance
        .onReceive(locationManager.$region.compactMap { $0 }) { newRegion in
            searchModel.update(region: newRegion)
        }

        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Red Clear pill button (now left of the settings icon)
                Button {
                    // Clear all estimator inputs
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
