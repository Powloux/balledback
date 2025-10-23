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
import UIKit

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

    // Basic details
    @State private var jobName: String = ""
    @State private var phoneNumber: String = ""
    @State private var jobLocation: String = ""

    // Window category counts (2x2 grid)
    @State private var groundCount: Int = 0
    @State private var secondCount: Int = 0
    @State private var threePlusCount: Int = 0
    @State private var basementCount: Int = 0

    // Per-tile price (per unit)
    @State private var groundPrice: Double = 0
    @State private var secondPrice: Double = 0
    @State private var threePlusPrice: Double = 0
    @State private var basementPrice: Double = 0

    // Per-tile pricing unit and unit menu state
    @State private var groundUnit: PricingUnit = .window
    @State private var secondUnit: PricingUnit = .window
    @State private var threePlusUnit: PricingUnit = .window
    @State private var basementUnit: PricingUnit = .window

    @State private var groundUnitMenuOpen: Bool = false
    @State private var secondUnitMenuOpen: Bool = false
    @State private var threePlusUnitMenuOpen: Bool = false
    @State private var basementUnitMenuOpen: Bool = false

    // Initial snapshots for dirty detection
    @State private var initialJobName: String = ""
    @State private var initialPhoneNumber: String = ""
    @State private var initialJobLocation: String = ""
    @State private var initialGroundCount: Int = 0
    @State private var initialSecondCount: Int = 0
    @State private var initialThreePlusCount: Int = 0
    @State private var initialBasementCount: Int = 0

    // Location and search models
    @StateObject private var locationManager = OneShotLocationManager()
    @StateObject private var searchModel = LocalSearchCompleterModel()

    // Control suggestions visibility
    @State private var showSuggestions = false

    // Confirm discard/save draft
    @State private var showDiscardDialog = false

    // New: alert for saving without a name
    @State private var showUnnamedSaveAlert = false

    // Focus for job name field
    @FocusState private var jobNameFocused: Bool

    // Expansion state per tile
    @State private var isGroundExpanded = false
    @State private var isSecondExpanded = false
    @State private var isThreePlusExpanded = false
    @State private var isBasementExpanded = false

    // Enable Save if either job name OR job location OR phone OR any window count has content
    private var hasAnyCounts: Bool {
        groundCount > 0 || secondCount > 0 || threePlusCount > 0 || basementCount > 0
    }
    private var canSave: Bool {
        let trimmedJobName = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = jobLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedJobName.isEmpty || !trimmedLocation.isEmpty || !trimmedPhone.isEmpty || hasAnyCounts
    }

    // Dirty check: any changes compared to initial values (including counts)
    private var isDirty: Bool {
        let j = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = jobLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        let ij = initialJobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ip = initialPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let il = initialJobLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        return j != ij
            || p != ip
            || l != il
            || groundCount != initialGroundCount
            || secondCount != initialSecondCount
            || threePlusCount != initialThreePlusCount
            || basementCount != initialBasementCount
    }

    // Derived: any unit menu open?
    private var anyUnitMenuOpen: Bool {
        groundUnitMenuOpen || secondUnitMenuOpen || threePlusUnitMenuOpen || basementUnitMenuOpen
    }

    init(source: EstimatorSource, existingEstimate: Estimate? = nil) {
        self.source = source
        self.existingEstimate = existingEstimate
    }

    var body: some View {
        ZStack {
            // Global tap-to-dismiss visual overlay (non-blocking)
            if anyUnitMenuOpen {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false) // do not block taps; we handle closing via the content gesture below
            }

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
                            .focused($jobNameFocused)
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

                    // Window Categories (fixed 2x2 grid of tiles)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exterior")
                            .font(.headline)

                        // Exactly two columns; add a small central gutter.
                        let columns = [
                            GridItem(.flexible(), spacing: 35, alignment: .top),
                            GridItem(.flexible(), spacing: 12, alignment: .top)
                        ]

                        // spacing: vertical spacing between rows
                        LazyVGrid(columns: columns, alignment: .center, spacing: 5) {
                            categoryTile(
                                title: "Ground Level",
                                count: $groundCount,
                                color: .blue,
                                isExpanded: $isGroundExpanded,
                                price: $groundPrice,
                                unit: $groundUnit,
                                isUnitMenuOpen: $groundUnitMenuOpen
                            )
                            .scaleEffect(0.95)

                            categoryTile(
                                title: "Second Story",
                                count: $secondCount,
                                color: .teal,
                                isExpanded: $isSecondExpanded,
                                price: $secondPrice,
                                unit: $secondUnit,
                                isUnitMenuOpen: $secondUnitMenuOpen
                            )
                            .scaleEffect(0.95)

                            categoryTile(
                                title: "3+ Story",
                                count: $threePlusCount,
                                color: .purple,
                                isExpanded: $isThreePlusExpanded,
                                price: $threePlusPrice,
                                unit: $threePlusUnit,
                                isUnitMenuOpen: $threePlusUnitMenuOpen
                            )
                            .scaleEffect(0.95)

                            categoryTile(
                                title: "Basement",
                                count: $basementCount,
                                color: .indigo,
                                isExpanded: $isBasementExpanded,
                                price: $basementPrice,
                                unit: $basementUnit,
                                isUnitMenuOpen: $basementUnitMenuOpen
                            )
                            .scaleEffect(0.95)
                        }
                        .padding(.top, 2)
                        .padding(.horizontal, 7) // Outer gutters so tiles don't hug screen edges
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                // Global tap-to-dismiss: close menus when tapping outside dropdowns
                .contentShape(Rectangle())
                .onTapGesture {
                    if anyUnitMenuOpen {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            groundUnitMenuOpen = false
                            secondUnitMenuOpen = false
                            threePlusUnitMenuOpen = false
                            basementUnitMenuOpen = false
                        }
                    }
                }
            }
        }
        .navigationTitle(existingEstimate == nil ? "" : "Edit Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)

        .onAppear {
            // Prefill fields when editing and capture initial values
            if let estimate = existingEstimate {
                jobName = estimate.jobName
                phoneNumber = estimate.phoneNumber
                jobLocation = estimate.jobLocation

                groundCount = estimate.groundCount
                secondCount = estimate.secondCount
                threePlusCount = estimate.threePlusCount
                basementCount = estimate.basementCount
            }

            // Capture initial values for dirty checking
            initialJobName = jobName
            initialPhoneNumber = phoneNumber
            initialJobLocation = jobLocation

            initialGroundCount = groundCount
            initialSecondCount = secondCount
            initialThreePlusCount = threePlusCount
            initialBasementCount = basementCount

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
                    let nameIsEmpty = jobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if nameIsEmpty && hasAnyCounts {
                        // Ask to confirm saving without a name
                        showUnnamedSaveAlert = true
                    } else {
                        finalizeAndDismiss(save: true)
                    }
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
                    groundCount = 0
                    secondCount = 0
                    threePlusCount = 0
                    basementCount = 0

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

        // Alert for saving without a name
        .alert("Save job without naming?", isPresented: $showUnnamedSaveAlert) {
            Button("Yes") {
                finalizeAndDismiss(save: true)
            }
            Button("Name") {
                // Focus the job name field for quick entry
                jobNameFocused = true
            }
        } message: {
            Text("You can always name it later.")
        }
    }

    // MARK: - Tile Builder

    @ViewBuilder
    private func categoryTile(
        title: String,
        count: Binding<Int>,
        color: Color,
        isExpanded: Binding<Bool>,
        price: Binding<Double>,
        unit: Binding<PricingUnit>,
        isUnitMenuOpen: Binding<Bool>
    ) -> some View {
        let collapsedHeight: CGFloat = 250

        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            // Controls row: − [count] +
            HStack(spacing: 12) {
                Button {
                    if count.wrappedValue > 0 {
                        count.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                }

                EditableCountField(count: count)
                    .frame(width: 60)

                Button {
                    count.wrappedValue += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Price row: "Price Per…" button with dropdown + price field
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isUnitMenuOpen.wrappedValue.toggle()
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Price Per…")
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .rotationEffect(.degrees(isUnitMenuOpen.wrappedValue ? 180 : 0))
                                .animation(.easeInOut(duration: 0.2), value: isUnitMenuOpen.wrappedValue)
                        }
                        .frame(minWidth: 0, idealWidth: 140, maxWidth: 160)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 6)

                    PriceField(value: price)
                        .frame(minWidth: 76, idealWidth: 88, maxWidth: 110, alignment: .trailing)
                }

                if isUnitMenuOpen.wrappedValue {
                    VStack(alignment: .leading, spacing: 8) {
                        // Window row
                        Button {
                            unit.wrappedValue = .window
                            // Keep menu open after selection
                        } label: {
                            HStack {
                                Text("Window")
                                    .font(.body)
                                    .foregroundStyle(unit.wrappedValue == .window ? .white : .primary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(unit.wrappedValue == .window ? Color.blue : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        // Consume taps so they don't bubble to the global onTapGesture
                        .highPriorityGesture(TapGesture())

                        // Pane row
                        Button {
                            unit.wrappedValue = .pane
                            // Keep menu open after selection
                        } label: {
                            HStack {
                                Text("Pane")
                                    .font(.body)
                                    .foregroundStyle(unit.wrappedValue == .pane ? .white : .primary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(unit.wrappedValue == .pane ? Color.blue : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        // Consume taps so they don't bubble to the global onTapGesture
                        .highPriorityGesture(TapGesture())
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    // Also consume taps anywhere in the dropdown container
                    .highPriorityGesture(TapGesture())
                }
            }
            .padding(.vertical, 4)

            // Expanded advanced content placeholder (above the bottom button)
            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Advanced options coming soon…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Label("Example toggle", systemImage: "slider.horizontal.3")
                        Spacer()
                        Toggle("", isOn: .constant(true))
                            .labelsHidden()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                    )
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut, value: isExpanded.wrappedValue)
            }

            // Bottom-aligned Advanced Modifiers button with increased vertical size and stacked text
            Button {
                withAnimation(.easeInOut) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced")
                        Text("Modifiers")
                    }
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded.wrappedValue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced Modifiers")
            .padding(.top, 4)
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: collapsedHeight,
            // Expand if either Advanced is open or the Price Per menu is open.
            maxHeight: (isExpanded.wrappedValue || isUnitMenuOpen.wrappedValue) ? .infinity : collapsedHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isUnitMenuOpen.wrappedValue)
    }

    // Small helper view to edit an Int count with numeric keyboard and validation
    private struct EditableCountField: View {
        @Binding var count: Int
        @State private var text: String = ""
        @FocusState private var isFocused: Bool

        var body: some View {
            TextField("0", text: Binding(
                get: {
                    if text.isEmpty { return String(count) }
                    return text
                },
                set: { newValue in
                    let digits = newValue.filter { $0.isNumber }
                    text = digits
                    if let val = Int(digits) {
                        count = max(0, val)
                    } else if digits.isEmpty {
                        count = 0
                    }
                }
            ))
            .keyboardType(.numberPad)
            .focused($isFocused)
            .multilineTextAlignment(.center)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .frame(minWidth: 50)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
            )
            .onAppear {
                text = String(count)
            }
            .onChange(of: count) { _, newValue in
                let current = Int(text) ?? 0
                if current != newValue {
                    text = String(newValue)
                }
            }
            .accessibilityLabel("Quantity")
        }
    }

    // Numeric price field for Double with validation and "$0.00" default
    private struct PriceField: View {
        @Binding var value: Double
        @State private var text: String = ""
        @FocusState private var isFocused: Bool

        var body: some View {
            TextField("$0.00", text: Binding(
                get: {
                    if text.isEmpty { return currencyString(from: value) }
                    return text
                },
                set: { newValue in
                    // Allow optional leading "$", digits, and one decimal point.
                    let filtered = filterCurrency(newValue)
                    text = filtered
                    let numeric = filtered.replacingOccurrences(of: "$", with: "")
                    if let v = Double(numeric) {
                        value = max(0, v)
                    } else if numeric.isEmpty {
                        value = 0
                    }
                }
            ))
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
            )
            .onAppear {
                text = currencyString(from: value)
            }
            .onChange(of: value) { _, newValue in
                let currentNumeric = Double(text.replacingOccurrences(of: "$", with: "")) ?? 0
                if abs(currentNumeric - newValue) > 0.0001 {
                    text = currencyString(from: newValue)
                }
            }
            .onChange(of: isFocused) { _, focused in
                // Reformat on focus loss to ensure "$x.xx"
                if !focused {
                    text = currencyString(from: value)
                }
            }
            .accessibilityLabel("Price per unit")
        }

        private func currencyString(from v: Double) -> String {
            // Always show $ with two decimals
            return String(format: "$%.2f", v)
        }

        private func filterCurrency(_ s: String) -> String {
            var result = ""
            var hasDot = false
            var hasDollar = false

            for (i, ch) in s.enumerated() {
                if ch == "$" && !hasDollar && i == 0 {
                    result.append(ch)
                    hasDollar = true
                } else if ch.isNumber {
                    result.append(ch)
                } else if ch == "." && !hasDot {
                    result.append(ch)
                    hasDot = true
                }
            }

            // Ensure leading "$"
            if !result.hasPrefix("$") {
                result = "$" + result
            }
            // Avoid lone "$" or "$."
            if result == "$" || result == "$." {
                result = "$0"
            }
            return result
        }
    }

    // MARK: - Save helper

    private func finalizeAndDismiss(save: Bool) {
        showSuggestions = false
        searchModel.query = ""

        guard save else {
            dismiss()
            return
        }

        // Default name if empty
        let trimmedName = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Untitled Estimate" : trimmedName

        let trimmed = Estimate(
            jobName: finalName,
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            jobLocation: jobLocation.trimmingCharacters(in: .whitespacesAndNewlines),
            groundCount: groundCount,
            secondCount: secondCount,
            threePlusCount: threePlusCount,
            basementCount: basementCount
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

// MARK: - Supporting types

private enum PricingUnit: String, CaseIterable, Identifiable {
    case window, pane
    var id: String { rawValue }
}

