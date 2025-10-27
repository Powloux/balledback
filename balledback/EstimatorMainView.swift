//
//  EstimatorMainView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI
import CoreLocation
import Combine
import UIKit
import MapKit

// MARK: - Preview helpers

enum Preview {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @discardableResult
    static func disableAnimations<T>(_ body: () -> T) -> T {
        if isActive {
            return withAnimation(nil, body)
        } else {
            return body()
        }
    }
}

private extension AnyTransition {
    static func previewSafe(_ transition: AnyTransition) -> AnyTransition {
        Preview.isActive ? .identity : transition
    }
}

// MARK: - Suggestion model (preview-friendly)

struct SuggestionItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
}

protocol SuggestionProviding: AnyObject {
    var query: String { get set }
    var resultsPublisher: AnyPublisher<[SuggestionItem], Never> { get }
    func update(region: MKCoordinateRegion?)
}

// MARK: - Real MapKit-backed provider (used at runtime)

@MainActor
final class MapKitSuggestionProvider: NSObject, SuggestionProviding {
    private let resultsSubject = CurrentValueSubject<[SuggestionItem], Never>([])
    var resultsPublisher: AnyPublisher<[SuggestionItem], Never> { resultsSubject.eraseToAnyPublisher() }

    private let completer: MKLocalSearchCompleter

    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func update(region: MKCoordinateRegion?) {
        if let region {
            completer.region = region
        }
    }

    var query: String = "" {
        didSet { completer.queryFragment = query }
    }
}

extension MapKitSuggestionProvider: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.map { SuggestionItem(title: $0.title, subtitle: $0.subtitle) }
        resultsSubject.send(mapped)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        resultsSubject.send([])
    }
}

// MARK: - Mock provider for Canvas previews (no MapKit use)

@MainActor
final class MockSuggestionProvider: SuggestionProviding {
    private let resultsSubject = CurrentValueSubject<[SuggestionItem], Never>([])
    var resultsPublisher: AnyPublisher<[SuggestionItem], Never> { resultsSubject.eraseToAnyPublisher() }

    func update(region: MKCoordinateRegion?) { /* no-op */ }

    var query: String = "" {
        didSet {
            guard !query.isEmpty else {
                resultsSubject.send([])
                return
            }
            // Simple fake data
            resultsSubject.send([
                SuggestionItem(title: "123 Main St", subtitle: "Springfield"),
                SuggestionItem(title: "456 Oak Ave", subtitle: "Shelbyville"),
                SuggestionItem(title: "789 Pine Rd", subtitle: "Ogdenville")
            ])
        }
    }
}

// MARK: - Simple location manager to get a one-time region for biasing search.

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

// MARK: - Modifiers seed

private func baseModifiersSeed() -> [AdvancedModifierItem] {
    [
        AdvancedModifierItem(name: "Hard water"),
        AdvancedModifierItem(name: "Difficult to clean"),
        AdvancedModifierItem(name: "Construction clean"),
        AdvancedModifierItem(name: "Paint scrape off"),
        AdvancedModifierItem(name: "French windows"),
        AdvancedModifierItem(name: "Large windows"),
        AdvancedModifierItem(name: "Accessibility"),
        AdvancedModifierItem(name: "Custom", isCustom: true)
    ]
}

// MARK: - Main View

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

    // Location and suggestions
    @StateObject private var locationManager = OneShotLocationManager()
    @State private var suggestions: [SuggestionItem] = []
    @State private var cancellableBag = Set<AnyCancellable>()
    private let suggestionProvider: SuggestionProviding

    // Control suggestions visibility
    @State private var showSuggestions = false

    // Confirm discard/save draft
    @State private var showDiscardDialog = false

    // Alert for saving without a name
    @State private var showUnnamedSaveAlert = false

    // Focus for job name field
    @FocusState private var jobNameFocused: Bool

    // Expansion state per tile
    @State private var isGroundExpanded = false
    @State private var isSecondExpanded = false
    @State private var isThreePlusExpanded = false
    @State private var isBasementExpanded = false

    // Scroll metrics for floating/locking bar
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffsetY: CGFloat = 0

    // Advanced modifiers per tile
    @State private var groundModifiers: [AdvancedModifierItem] = baseModifiersSeed()
    @State private var secondModifiers: [AdvancedModifierItem] = baseModifiersSeed()
    @State private var threePlusModifiers: [AdvancedModifierItem] = baseModifiersSeed()
    @State private var basementModifiers: [AdvancedModifierItem] = baseModifiersSeed()

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

    // MARK: - Grand total

    private let barHeight: CGFloat = 64
    private let bottomThreshold: CGFloat = 32

    private var grandTotal: Double {
        Double(groundCount) * groundPrice
        + Double(secondCount) * secondPrice
        + Double(threePlusCount) * threePlusPrice
        + Double(basementCount) * basementPrice
    }

    private var nearBottom: Bool {
        if Preview.isActive { return false }
        guard contentHeight > 0, viewportHeight > 0 else { return false }
        let maxOffset = max(0, contentHeight - viewportHeight)
        return (maxOffset - scrollOffsetY) <= bottomThreshold
    }

    init(source: EstimatorSource, existingEstimate: Estimate? = nil, suggestionProvider: SuggestionProviding? = nil) {
        self.source = source
        self.existingEstimate = existingEstimate
        // Inject or choose default provider (mock for previews, MapKit for runtime)
        if let injected = suggestionProvider {
            self.suggestionProvider = injected
        } else {
            self.suggestionProvider = Preview.isActive ? MockSuggestionProvider() : MapKitSuggestionProvider()
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ViewportReader(viewportChanged: { viewportHeight = $0 }) {
                ScrollContent(
                    jobName: $jobName,
                    phoneNumber: $phoneNumber,
                    jobLocation: $jobLocation,
                    showSuggestions: $showSuggestions,
                    suggestions: suggestions,
                    onSuggestionTapped: { item in
                        let combined = item.title.isEmpty ? item.subtitle : "\(item.title) \(item.subtitle)"
                        jobLocation = combined.trimmingCharacters(in: .whitespacesAndNewlines)
                        showSuggestions = false
                    },
                    onJobLocationChanged: { newValue in
                        if !Preview.isActive {
                            suggestionProvider.query = newValue
                        }
                        showSuggestions = !newValue.isEmpty
                    },
                    groundCount: $groundCount,
                    secondCount: $secondCount,
                    threePlusCount: $threePlusCount,
                    basementCount: $basementCount,
                    groundPrice: $groundPrice,
                    secondPrice: $secondPrice,
                    threePlusPrice: $threePlusPrice,
                    basementPrice: $basementPrice,
                    groundUnit: $groundUnit,
                    secondUnit: $secondUnit,
                    threePlusUnit: $threePlusUnit,
                    basementUnit: $basementUnit,
                    groundUnitMenuOpen: $groundUnitMenuOpen,
                    secondUnitMenuOpen: $secondUnitMenuOpen,
                    threePlusUnitMenuOpen: $threePlusUnitMenuOpen,
                    basementUnitMenuOpen: $basementUnitMenuOpen,
                    isGroundExpanded: $isGroundExpanded,
                    isSecondExpanded: $isSecondExpanded,
                    isThreePlusExpanded: $isThreePlusExpanded,
                    isBasementExpanded: $isBasementExpanded,
                    nearBottom: nearBottom,
                    barHeight: barHeight,
                    // Advanced modifiers bindings
                    groundModifiers: $groundModifiers,
                    secondModifiers: $secondModifiers,
                    threePlusModifiers: $threePlusModifiers,
                    basementModifiers: $basementModifiers
                )
                .onContentHeightChanged { contentHeight = $0 }
            }

            // Floating overlay version when not near bottom
            if !nearBottom {
                GrandTotalBar(total: grandTotal)
                    .frame(height: barHeight)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.previewSafe(.move(edge: .bottom).combined(with: .opacity)))
            }
        }
        .background(
            Group {
                if !Preview.isActive {
                    GeometryReader { _ in
                        Color.clear
                            .overlay(
                                ScrollOffsetReader(offsetChanged: { offset in
                                    scrollOffsetY = offset
                                })
                            )
                    }
                } else {
                    Color.clear
                }
            }
        )

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

                groundPrice = estimate.groundPrice
                secondPrice = estimate.secondPrice
                threePlusPrice = estimate.threePlusPrice
                basementPrice = estimate.basementPrice

                groundUnit = estimate.groundUnit
                secondUnit = estimate.secondUnit
                threePlusUnit = estimate.threePlusUnit
                basementUnit = estimate.basementUnit

                // Load modifiers if present
                if let gm = estimate.groundModifiers { groundModifiers = gm }
                if let sm = estimate.secondModifiers { secondModifiers = sm }
                if let tm = estimate.threePlusModifiers { threePlusModifiers = tm }
                if let bm = estimate.basementModifiers { basementModifiers = bm }
            }

            // Capture initial values for dirty checking
            initialJobName = jobName
            initialPhoneNumber = phoneNumber
            initialJobLocation = jobLocation

            initialGroundCount = groundCount
            initialSecondCount = secondCount
            initialThreePlusCount = threePlusCount
            initialBasementCount = basementCount

            // Subscribe to suggestions
            suggestionProvider.resultsPublisher
                .receive(on: DispatchQueue.main)
                .sink { items in
                    self.suggestions = items
                }
                .store(in: &cancellableBag)

            // Request user location once to bias results (not in previews)
            if !Preview.isActive {
                locationManager.request()
            }
        }
        .onReceive(locationManager.$region.compactMap { $0 }) { newRegion in
            suggestionProvider.update(region: newRegion)
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

                    groundPrice = 0
                    secondPrice = 0
                    threePlusPrice = 0
                    basementPrice = 0

                    groundUnit = .window
                    secondUnit = .window
                    threePlusUnit = .window
                    basementUnit = .window

                    // Reset modifiers to base seeds
                    groundModifiers = baseModifiersSeed()
                    secondModifiers = baseModifiersSeed()
                    threePlusModifiers = baseModifiersSeed()
                    basementModifiers = baseModifiersSeed()

                    if !Preview.isActive {
                        suggestionProvider.query = ""
                    }
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

    // MARK: - Save helper

    private func finalizeAndDismiss(save: Bool) {
        showSuggestions = false
        if !Preview.isActive {
            suggestionProvider.query = ""
        }

        guard save else {
            dismiss()
            return
        }

        // Default name if empty
        let trimmedName = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Untitled Estimate" : trimmedName

        // Include modifiers for persistence
        let trimmed = Estimate(
            jobName: finalName,
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            jobLocation: jobLocation.trimmingCharacters(in: .whitespacesAndNewlines),
            groundCount: groundCount,
            secondCount: secondCount,
            threePlusCount: threePlusCount,
            basementCount: basementCount,
            groundPrice: groundPrice,
            secondPrice: secondPrice,
            threePlusPrice: threePlusPrice,
            basementPrice: basementPrice,
            groundUnit: groundUnit,
            secondUnit: secondUnit,
            threePlusUnit: threePlusUnit,
            basementUnit: basementUnit,
            groundModifiers: groundModifiers,
            secondModifiers: secondModifiers,
            threePlusModifiers: threePlusModifiers,
            basementModifiers: basementModifiers
        )

        if let existing = existingEstimate {
            store.update(id: existing.id, with: trimmed, from: source)
        } else {
            store.add(trimmed, from: source)
        }
        dismiss()
    }
}

// MARK: - Scroll metrics tracking

private struct ScrollMetrics: Equatable {
    var contentHeight: CGFloat?
}

private struct ScrollMetricsPreferenceKey: PreferenceKey {
    static var defaultValue: ScrollMetrics = ScrollMetrics(contentHeight: nil)
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        let next = nextValue()
        if let ch = next.contentHeight {
            value.contentHeight = ch
        }
    }
}

// Helper to read scroll offset by anchoring to a named coordinate space
private struct ScrollOffsetReader: View {
    let offsetChanged: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("ScrollArea")).minY * -1)
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            offsetChanged(value)
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Grand total bar view
private struct GrandTotalBar: View {
    let total: Double

    var body: some View {
        HStack(spacing: 10) {
            Text("Grand total:")
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(String(format: "$%.2f", total))
                .font(.headline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Extracted helpers to simplify body

private struct ViewportReader<Content: View>: View {
    let viewportChanged: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { outerGeo in
            let vpHeight: CGFloat = outerGeo.size.height
            Color.clear
                .onAppear { viewportChanged(vpHeight) }
                .onChange(of: vpHeight) { _, newVal in viewportChanged(newVal) }

            content()
        }
    }
}

private struct ScrollContent: View {
    // Bindings and state
    @Binding var jobName: String
    @Binding var phoneNumber: String
    @Binding var jobLocation: String

    @Binding var showSuggestions: Bool
    let suggestions: [SuggestionItem]
    let onSuggestionTapped: (SuggestionItem) -> Void
    let onJobLocationChanged: (String) -> Void

    @Binding var groundCount: Int
    @Binding var secondCount: Int
    @Binding var threePlusCount: Int
    @Binding var basementCount: Int

    @Binding var groundPrice: Double
    @Binding var secondPrice: Double
    @Binding var threePlusPrice: Double
    @Binding var basementPrice: Double

    @Binding var groundUnit: PricingUnit
    @Binding var secondUnit: PricingUnit
    @Binding var threePlusUnit: PricingUnit
    @Binding var basementUnit: PricingUnit

    @Binding var groundUnitMenuOpen: Bool
    @Binding var secondUnitMenuOpen: Bool
    @Binding var threePlusUnitMenuOpen: Bool
    @Binding var basementUnitMenuOpen: Bool

    @Binding var isGroundExpanded: Bool
    @Binding var isSecondExpanded: Bool
    @Binding var isThreePlusExpanded: Bool
    @Binding var isBasementExpanded: Bool

    let nearBottom: Bool
    let barHeight: CGFloat

    // Advanced modifiers per tile
    @Binding var groundModifiers: [AdvancedModifierItem]
    @Binding var secondModifiers: [AdvancedModifierItem]
    @Binding var threePlusModifiers: [AdvancedModifierItem]
    @Binding var basementModifiers: [AdvancedModifierItem]

    // Preference writer
    var onContentHeightChanged: (CGFloat) -> Void = { _ in }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 35, alignment: .top),
            GridItem(.flexible(), spacing: 12, alignment: .top)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JobNameField(jobName: $jobName)

                PhoneField(phoneNumber: $phoneNumber)

                LocationField(
                    jobLocation: $jobLocation,
                    showSuggestions: $showSuggestions,
                    suggestions: suggestions,
                    onSuggestionTapped: onSuggestionTapped,
                    onChange: onJobLocationChanged
                )

                WindowCategoriesGrid(
                    columns: columns,
                    groundCount: $groundCount,
                    secondCount: $secondCount,
                    threePlusCount: $threePlusCount,
                    basementCount: $basementCount,
                    groundPrice: $groundPrice,
                    secondPrice: $secondPrice,
                    threePlusPrice: $threePlusPrice,
                    basementPrice: $basementPrice,
                    groundUnit: $groundUnit,
                    secondUnit: $secondUnit,
                    threePlusUnit: $threePlusUnit,
                    basementUnit: $basementUnit,
                    groundUnitMenuOpen: $groundUnitMenuOpen,
                    secondUnitMenuOpen: $secondUnitMenuOpen,
                    threePlusUnitMenuOpen: $threePlusUnitMenuOpen,
                    basementUnitMenuOpen: $basementUnitMenuOpen,
                    isGroundExpanded: $isGroundExpanded,
                    isSecondExpanded: $isSecondExpanded,
                    isThreePlusExpanded: $isThreePlusExpanded,
                    isBasementExpanded: $isBasementExpanded,
                    groundModifiers: $groundModifiers,
                    secondModifiers: $secondModifiers,
                    threePlusModifiers: $threePlusModifiers,
                    basementModifiers: $basementModifiers
                )

                if nearBottom {
                    // Footer version of the Grand Total bar when near bottom (locks in)
                    let total =
                        Double(groundCount) * groundPrice
                        + Double(secondCount) * secondPrice
                        + Double(threePlusCount) * threePlusPrice
                        + Double(basementCount) * basementPrice

                    GrandTotalBar(total: total)
                        .frame(height: barHeight)
                        .padding(.top, 8)
                }

                // Spacer to avoid overlay overlap
                if !nearBottom {
                    Spacer().frame(height: barHeight + 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                Group {
                    if !Preview.isActive {
                        GeometryReader { contentGeo in
                            Color.clear
                                .preference(key: ScrollMetricsPreferenceKey.self, value: ScrollMetrics(
                                    contentHeight: contentGeo.size.height
                                ))
                        }
                    } else {
                        Color.clear
                    }
                }
            )
        }
        .coordinateSpace(name: "ScrollArea")
        .onPreferenceChange(ScrollMetricsPreferenceKey.self) { metrics in
            if let ch = metrics.contentHeight {
                onContentHeightChanged(ch)
            }
        }
    }

    func onContentHeightChanged(_ perform: @escaping (CGFloat) -> Void) -> some View {
        var copy = self
        copy.onContentHeightChanged = perform
        return copy
    }
}

// MARK: Small extracted sections

private struct JobNameField: View {
    @Binding var jobName: String
    @FocusState private var focused: Bool

    init(jobName: Binding<String>) {
        _jobName = jobName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job Name")
                .font(.headline)

            TextField("Enter job name", text: $jobName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
        }
    }
}

private struct PhoneField: View {
    @Binding var phoneNumber: String

    init(phoneNumber: Binding<String>) {
        _phoneNumber = phoneNumber
    }

    var body: some View {
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
    }
}

private struct LocationField: View {
    @Binding var jobLocation: String
    @Binding var showSuggestions: Bool
    let suggestions: [SuggestionItem]
    let onSuggestionTapped: (SuggestionItem) -> Void
    let onChange: (String) -> Void

    init(
        jobLocation: Binding<String>,
        showSuggestions: Binding<Bool>,
        suggestions: [SuggestionItem],
        onSuggestionTapped: @escaping (SuggestionItem) -> Void,
        onChange: @escaping (String) -> Void
    ) {
        _jobLocation = jobLocation
        _showSuggestions = showSuggestions
        self.suggestions = suggestions
        self.onSuggestionTapped = onSuggestionTapped
        self.onChange = onChange
    }

    var body: some View {
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
                onChange(newValue)
            }

            if showSuggestions && !suggestions.isEmpty {
                SuggestionsList(suggestions: suggestions, onTap: onSuggestionTapped)
            }
        }
    }
}

private struct SuggestionsList: View {
    let suggestions: [SuggestionItem]
    let onTap: (SuggestionItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { item in
                Button {
                    onTap(item)
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

                if item.id != suggestions.last?.id {
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

private struct WindowCategoriesGrid: View {
    let columns: [GridItem]

    @Binding var groundCount: Int
    @Binding var secondCount: Int
    @Binding var threePlusCount: Int
    @Binding var basementCount: Int

    @Binding var groundPrice: Double
    @Binding var secondPrice: Double
    @Binding var threePlusPrice: Double
    @Binding var basementPrice: Double

    @Binding var groundUnit: PricingUnit
    @Binding var secondUnit: PricingUnit
    @Binding var threePlusUnit: PricingUnit
    @Binding var basementUnit: PricingUnit

    @Binding var groundUnitMenuOpen: Bool
    @Binding var secondUnitMenuOpen: Bool
    @Binding var threePlusUnitMenuOpen: Bool
    @Binding var basementUnitMenuOpen: Bool

    @Binding var isGroundExpanded: Bool
    @Binding var isSecondExpanded: Bool
    @Binding var isThreePlusExpanded: Bool
    @Binding var isBasementExpanded: Bool

    // Advanced modifiers per tile
    @Binding var groundModifiers: [AdvancedModifierItem]
    @Binding var secondModifiers: [AdvancedModifierItem]
    @Binding var threePlusModifiers: [AdvancedModifierItem]
    @Binding var basementModifiers: [AdvancedModifierItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exterior")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .center, spacing: 5) {
                categoryTile(
                    title: "Ground Level",
                    count: $groundCount,
                    color: Color.blue,
                    isExpanded: $isGroundExpanded,
                    price: $groundPrice,
                    unit: $groundUnit,
                    isUnitMenuOpen: $groundUnitMenuOpen,
                    modifiers: $groundModifiers
                )
                .scaleEffect(0.95)

                categoryTile(
                    title: "Second Story",
                    count: $secondCount,
                    color: Color.teal,
                    isExpanded: $isSecondExpanded,
                    price: $secondPrice,
                    unit: $secondUnit,
                    isUnitMenuOpen: $secondUnitMenuOpen,
                    modifiers: $secondModifiers
                )
                .scaleEffect(0.95)

                categoryTile(
                    title: "3+ Story",
                    count: $threePlusCount,
                    color: Color.purple,
                    isExpanded: $isThreePlusExpanded,
                    price: $threePlusPrice,
                    unit: $threePlusUnit,
                    isUnitMenuOpen: $threePlusUnitMenuOpen,
                    modifiers: $threePlusModifiers
                )
                .scaleEffect(0.95)

                categoryTile(
                    title: "Basement",
                    count: $basementCount,
                    color: Color.indigo,
                    isExpanded: $isBasementExpanded,
                    price: $basementPrice,
                    unit: $basementUnit,
                    isUnitMenuOpen: $basementUnitMenuOpen,
                    modifiers: $basementModifiers
                )
                .scaleEffect(0.95)
            }
            .padding(.top, 2)
            .padding(.horizontal, 7)
        }
    }

    // Moved here so it's in scope for WindowCategoriesGrid
    @ViewBuilder
    private func categoryTile(
        title: String,
        count: Binding<Int>,
        color: Color,
        isExpanded: Binding<Bool>,
        price: Binding<Double>,
        unit: Binding<PricingUnit>,
        isUnitMenuOpen: Binding<Bool>,
        modifiers: Binding<[AdvancedModifierItem]>
    ) -> some View {
        let collapsedHeight: CGFloat = 300
        let dropdownTransition: AnyTransition = .previewSafe(.opacity.combined(with: .move(edge: .top)))

        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: Alignment.center)
                .multilineTextAlignment(.center)

            CountControlsRow(count: count)

            VStack(alignment: .leading, spacing: 6) {
                PricePerRow(isUnitMenuOpen: isUnitMenuOpen, price: price)

                if isUnitMenuOpen.wrappedValue {
                    UnitDropdownMenu(unit: unit)
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
                        .transition(dropdownTransition)
                        .highPriorityGesture(TapGesture())
                }

                let total = Double(count.wrappedValue) * price.wrappedValue
                HStack(spacing: 6) {
                    Text("Current total:")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(String(format: "$%.2f", total))
                        .font(.headline.weight(.semibold))
                        .kerning(-0.1)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)

            if !isExpanded.wrappedValue {
                Spacer(minLength: 8)
            }

            Button {
                withAnimation(Preview.isActive ? nil : .easeInOut) {
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

                    let chevronRotation = Angle(degrees: isExpanded.wrappedValue ? 180 : 0)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(chevronRotation)
                        .animation(Preview.isActive ? nil : .easeInOut(duration: 0.2), value: isExpanded.wrappedValue)
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
            .padding(.bottom, 8)

            if isExpanded.wrappedValue {
                AdvancedOptionsBlock(modifiers: modifiers)
                    .padding(.top, 2)
                    .transition(.previewSafe(.opacity.combined(with: .move(edge: .top))))
                    .animation(Preview.isActive ? nil : .easeInOut, value: isExpanded.wrappedValue)
            }
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: collapsedHeight,
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
        .animation(Preview.isActive ? nil : .easeInOut(duration: 0.2), value: isUnitMenuOpen.wrappedValue)
    }

    // Copied helpers localized to the grid scope

    private struct CountControlsRow: View {
        @Binding var count: Int

        init(count: Binding<Int>) {
            self._count = count
        }

        var body: some View {
            HStack(spacing: 12) {
                Button {
                    if count > 0 {
                        count -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                }

                EditableCountField(count: $count)
                    .frame(width: 60)

                Button {
                    count += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct PricePerRow: View {
        @Binding var isUnitMenuOpen: Bool
        @Binding var price: Double

        init(isUnitMenuOpen: Binding<Bool>, price: Binding<Double>) {
            self._isUnitMenuOpen = isUnitMenuOpen
            self._price = price
        }

        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isUnitMenuOpen.toggle()
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text("Price Per…")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        let chevronRotation = Angle(degrees: isUnitMenuOpen ? 180 : 0)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .rotationEffect(chevronRotation)
                            .animation(.easeInOut(duration: 0.2), value: isUnitMenuOpen)
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

                PriceField(value: $price)
                    .frame(minWidth: 85, idealWidth: 100, maxWidth: 110, alignment: .center)
            }
        }
    }

    private struct UnitDropdownMenu: View {
        @Binding var unit: PricingUnit

        init(unit: Binding<PricingUnit>) {
            self._unit = unit
        }

        var body: some View {
            VStack(spacing: 8) {
                Picker("", selection: $unit) {
                    Text("Window").tag(PricingUnit.window as PricingUnit)
                    Text("Pane").tag(PricingUnit.pane as PricingUnit)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // Advanced Modifiers UI
    private struct AdvancedOptionsBlock: View {
        @Binding var modifiers: [AdvancedModifierItem]

        init(modifiers: Binding<[AdvancedModifierItem]>) {
            self._modifiers = modifiers
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($modifiers) { $item in
                    ModifierRow(item: $item)
                }

                Button {
                    addCustom()
                } label: {
                    Label("Add Custom", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }

        private func addCustom() {
            // Create a unique default name like "Custom 2", "Custom 3", ...
            let existingCustoms = modifiers.filter { $0.isCustom }
            let nextIndex = existingCustoms.count + 1
            let defaultName = existingCustoms.isEmpty ? "Custom" : "Custom \(nextIndex)"

            // Defer to next runloop tick and disable implicit animation to avoid Canvas thrash.
            DispatchQueue.main.async {
                Preview.disableAnimations {
                    modifiers.append(AdvancedModifierItem(name: defaultName, isCustom: true))
                }
            }
        }

        private struct ModifierRow: View {
            @Binding var item: AdvancedModifierItem
            @State private var priceText: String = ""
            @State private var multiplierText: String = ""

            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    // Title / name (editable if custom)
                    if item.isCustom {
                        TextField("Custom name", text: $item.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                    }

                    // Mode selector
                    Picker("", selection: $item.mode) {
                        Text(AdvancedModifierMode.price.title).tag(AdvancedModifierMode.price)
                        Text(AdvancedModifierMode.multiplier.title).tag(AdvancedModifierMode.multiplier)
                    }
                    .pickerStyle(.segmented)

                    // Input field based on mode
                    HStack {
                        if item.mode == .price {
                            PriceInput(value: $item.priceValue, text: $priceText)
                        } else {
                            MultiplierInput(value: $item.multiplierValue, text: $multiplierText)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .onAppear {
                    if priceText.isEmpty {
                        priceText = Self.currencyString(from: item.priceValue)
                    }
                    if multiplierText.isEmpty {
                        multiplierText = Self.multiplierString(from: item.multiplierValue)
                    }
                }
                .onChange(of: item.priceValue) { _, newVal in
                    let cur = Self.parseCurrency(priceText)
                    if abs(cur - newVal) > 0.0001 {
                        priceText = Self.currencyString(from: newVal)
                    }
                }
                .onChange(of: item.multiplierValue) { _, newVal in
                    let cur = Self.parseMultiplier(multiplierText)
                    if abs(cur - newVal) > 0.0001 {
                        multiplierText = Self.multiplierString(from: newVal)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemBackground))
                )
            }

            // MARK: - Static helpers to allow nested types to call them
            static func currencyString(from v: Double) -> String {
                String(format: "$%.2f", v)
            }
            static func multiplierString(from v: Double) -> String {
                if abs(v.rounded() - v) < 0.0001 {
                    return "x\(Int(v))"
                }
                return "x\(v)"
            }
            static func parseCurrency(_ s: String) -> Double {
                Double(s.replacingOccurrences(of: "$", with: "")) ?? 0
            }
            static func parseMultiplier(_ s: String) -> Double {
                Double(s.replacingOccurrences(of: "x", with: "")) ?? 1.0
            }
            static func filterCurrency(_ s: String) -> String {
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

                if !result.hasPrefix("$") {
                    result = "$" + result
                }
                if result == "$" || result == "$." {
                    result = "$0"
                }
                return result
            }
            static func filterMultiplier(_ s: String) -> String {
                var result = ""
                var hasDot = false
                var hasX = false

                for (i, ch) in s.enumerated() {
                    if (ch == "x" || ch == "X") && !hasX && i == 0 {
                        result.append("x")
                        hasX = true
                    } else if ch.isNumber {
                        result.append(ch)
                    } else if ch == "." && !hasDot {
                        result.append(ch)
                        hasDot = true
                    }
                }

                if !result.hasPrefix("x") {
                    result = "x" + result
                }
                if result == "x" || result == "x." {
                    result = "x1"
                }
                return result
            }

            // Price input similar to other currency fields
            private struct PriceInput: View {
                @Binding var value: Double
                @Binding var text: String
                @FocusState private var focused: Bool

                var body: some View {
                    TextField("$0.00", text: Binding(
                        get: {
                            if text.isEmpty { return ModifierRow.currencyString(from: value) }
                            return text
                        },
                        set: { newValue in
                            let filtered = ModifierRow.filterCurrency(newValue)
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
                    .focused($focused)
                    .multilineTextAlignment(.leading)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .onChange(of: focused) { _, f in
                        if !f {
                            text = ModifierRow.currencyString(from: value)
                        }
                    }
                    .accessibilityLabel("Modifier price")
                }
            }

            private struct MultiplierInput: View {
                @Binding var value: Double
                @Binding var text: String
                @FocusState private var focused: Bool

                var body: some View {
                    TextField("x1", text: Binding(
                        get: {
                            if text.isEmpty { return ModifierRow.multiplierString(from: value) }
                            return text
                        },
                        set: { newValue in
                            let filtered = ModifierRow.filterMultiplier(newValue)
                            text = filtered
                            let numeric = filtered.replacingOccurrences(of: "x", with: "")
                            if let v = Double(numeric) {
                                value = max(0, v)
                            } else if numeric.isEmpty {
                                value = 1.0
                            }
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.leading)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .onChange(of: focused) { _, f in
                        if !f {
                            text = ModifierRow.multiplierString(from: value)
                        }
                    }
                    .accessibilityLabel("Modifier multiplier")
                }
            }
        }
    }

    // Localized versions so they are in scope for the grid/tile
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
            .multilineTextAlignment(.center)
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
                if !focused {
                    text = currencyString(from: value)
                }
            }
            .accessibilityLabel("Price per unit")
        }

        private func currencyString(from v: Double) -> String {
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

            if !result.hasPrefix("$") {
                result = "$" + result
                       }
            if result == "$" || result == "$." {
                result = "$0"
            }
            return result
        }
    }
}

#Preview {
    NavigationStack {
        // Use mock provider so Canvas never touches MapKit/CoreLocation
        EstimatorMainView(source: .standard, suggestionProvider: MockSuggestionProvider())
            .environmentObject(EstimatorStore())
    }
}
