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

    // New: per-tile breakdown toggle
    @State private var showGroundBreakdown = false
    @State private var showSecondBreakdown = false
    @State private var showThreePlusBreakdown = false
    @State private var showBasementBreakdown = false

    // Scroll metrics for floating/locking bar
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffsetY: CGFloat = 0

    // Advanced modifiers per tile
    @State private var groundModifiers: [AdvancedModifierItem] = baseModifiersSeed()
    @State private var secondModifiers: [AdvancedModifierItem] = baseModifiersSeed()
    @State private var threePlusModifiers: [AdvancedModifierItem] = baseModifiersSeed()
    @State private var basementModifiers: [AdvancedModifierItem] = baseModifiersSeed()

    // Freeze scroll during layout-affecting toggles
    @State private var isScrollFrozen: Bool = false

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

    // MARK: - Grand total and itemization

    private let barHeight: CGFloat = 64
    private let bottomThreshold: CGFloat = 32

    private var baseSubtotal: Double {
        let groundBase = Double(max(0, groundCount)) * max(0, groundPrice)
        let secondBase = Double(max(0, secondCount)) * max(0, secondPrice)
        let threeBase = Double(max(0, threePlusCount)) * max(0, threePlusPrice)
        let basementBase = Double(max(0, basementCount)) * max(0, basementPrice)
        return groundBase + secondBase + threeBase + basementBase
    }

    // Updated grand total to include modifiers from each tile
    private var grandTotal: Double {
        let ground = tileTotal(count: groundCount, basePrice: groundPrice, modifiers: groundModifiers)
        let second = tileTotal(count: secondCount, basePrice: secondPrice, modifiers: secondModifiers)
        let threePlus = tileTotal(count: threePlusCount, basePrice: threePlusPrice, modifiers: threePlusModifiers)
        let basement = tileTotal(count: basementCount, basePrice: basementPrice, modifiers: basementModifiers)
        return ground + second + threePlus + basement
    }

    private var modifiersSubtotal: Double {
        max(0, grandTotal - baseSubtotal)
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
                    // breakdown toggles
                    showGroundBreakdown: $showGroundBreakdown,
                    showSecondBreakdown: $showSecondBreakdown,
                    showThreePlusBreakdown: $showThreePlusBreakdown,
                    showBasementBreakdown: $showBasementBreakdown,
                    nearBottom: nearBottom,
                    barHeight: barHeight,
                    // Advanced modifiers bindings
                    groundModifiers: $groundModifiers,
                    secondModifiers: $secondModifiers,
                    threePlusModifiers: $threePlusModifiers,
                    basementModifiers: $basementModifiers,
                    // Bottom itemization values
                    baseSubtotal: baseSubtotal,
                    modifiersSubtotal: modifiersSubtotal,
                    // Freeze binding
                    isScrollFrozen: $isScrollFrozen
                )
                .onContentHeightChanged { contentHeight = $0 }
            }

            // Always-mounted overlay bar; fade/hit-test based on nearBottom to avoid view tree swaps.
         //   GrandTotalBar(total: grandTotal)
               // .frame(height: barHeight)
               // .padding(.horizontal, 12)
               // .padding(.bottom, 8)
               // .opacity(nearBottom ? 0 : 1)
               // .allowsHitTesting(!nearBottom)
        }
        .safeAreaInset(edge: .bottom) {
            GrandTotalBar(total: grandTotal)
                .frame(height: barHeight)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }

        // Prevent keyboard safe-area adjustments from nudging the scroll when focusing fields
        .ignoresSafeArea(.keyboard)
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

        .navigationTitle(existingEstimate == nil ? "New Estimate" : "Edit Estimate")
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
        // Use the latest reported offset (no summation to avoid ambiguity)
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

// MARK: - Freeze scroll utility

private struct FreezeScroll {
    static func perform(in coordinateSpace: String, isFrozen: Binding<Bool>, _ changes: @escaping () -> Void) {
        // Disable scrolling and perform changes next runloop to allow ScrollView to compute current offset.
        isFrozen.wrappedValue = true
        DispatchQueue.main.async {
            withAnimation(nil) {
                changes()
            }
            // Re-enable scrolling on the next tick after layout settles.
            DispatchQueue.main.async {
                isFrozen.wrappedValue = false
            }
        }
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

// Bottom itemization (moved above ScrollContent so it's visible there)
private struct BottomItemizationView: View {
    let baseSubtotal: Double
    let modifiersSubtotal: Double

    // Inputs required to render breakdowns
    var groundCount: Int = 0
    var secondCount: Int = 0
    var threePlusCount: Int = 0
    var basementCount: Int = 0

    var groundPrice: Double = 0
    var secondPrice: Double = 0
    var threePlusPrice: Double = 0
    var basementPrice: Double = 0

    var groundModifiers: [AdvancedModifierItem] = []
    var secondModifiers: [AdvancedModifierItem] = []
    var threePlusModifiers: [AdvancedModifierItem] = []
    var basementModifiers: [AdvancedModifierItem] = []

    // Expansion toggles for each card
    @State private var showBaseBreakdown = false
    @State private var showModifiersBreakdown = false

   
    var body: some View {
        VStack(spacing: 12) {
            ItemRowCard(
                title: "Window Total",
                amount: baseSubtotal,
                isExpanded: $showBaseBreakdown
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    // Per-category lines (only if count > 0)
                    categoryLine(title: "Ground", count: groundCount, price: groundPrice)
                    categoryLine(title: "Second", count: secondCount, price: secondPrice)
                    categoryLine(title: "3+ Story", count: threePlusCount, price: threePlusPrice)
                    categoryLine(title: "Basement", count: basementCount, price: basementPrice)

                    Divider().padding(.vertical, 4)

                    HStack {
                        Text("Subtotal")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Text(currency(baseSubtotal))
                            .font(.footnote.weight(.semibold))
                    }
                }
            }

            ItemRowCard(
                title: "Modifiers total",
                amount: modifiersSubtotal,
                isExpanded: $showModifiersBreakdown
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    // Per-modifier contributions by tile
                    modifierSection(title: "Ground", count: groundCount, basePrice: groundPrice, modifiers: groundModifiers)
                    modifierSection(title: "Second", count: secondCount, basePrice: secondPrice, modifiers: secondModifiers)
                    modifierSection(title: "3+ Story", count: threePlusCount, basePrice: threePlusPrice, modifiers: threePlusModifiers)
                    modifierSection(title: "Basement", count: basementCount, basePrice: basementPrice, modifiers: basementModifiers)

                    Divider().padding(.vertical, 4)

                    HStack {
                        Text("Subtotal")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Text(currency(modifiersSubtotal))
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .transaction { txn in
            txn.disablesAnimations = true
        }
    }

    private func currency(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    @ViewBuilder
    private func categoryLine(title: String, count: Int, price: Double) -> some View {
        if count > 0, price >= 0 {
            let subtotal = Double(count) * max(0, price)
            HStack {
                Text(title + ":")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count) × \(currency(max(0, price))) = \(currency(subtotal))")
            }
            .font(.footnote)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func modifierSection(title: String, count: Int, basePrice: Double, modifiers: [AdvancedModifierItem]) -> some View {
        let safeBase = max(0, basePrice)
        let active = modifiers.filter { $0.quantity > 0 }
        if count > 0, !active.isEmpty, safeBase >= 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(active) { mod in
                    if mod.mode == .price, mod.priceValue >= 0 {
                        let qty = Double(min(mod.quantity, count))
                        let add = qty * mod.priceValue
                        if add > 0 {
                            HStack {
                                Text("\(mod.name):")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(qty)) × \(currency(mod.priceValue)) = \(currency(add))")
                            }
                            .font(.footnote)
                        }
                    } else if mod.mode == .multiplier, mod.multiplierValue >= 0 {
                        let qty = Double(min(mod.quantity, count))
                        let delta = max(0, mod.multiplierValue - 1.0)
                        let add = qty * safeBase * delta
                        if add > 0 {
                            HStack {
                                Text("\(mod.name):")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(qty)) × \(currency(safeBase)) × (x\(trim(mult: mod.multiplierValue)) − 1) = \(currency(add))")
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
            )
        } else {
            EmptyView()
        }
    }

    private func trim(mult v: Double) -> String {
        if abs(v.rounded() - v) < 0.0001 {
            return "\(Int(v))"
        }
        return String(v)
    }

    private struct ItemRowCard<Expanded: View>: View {
        let title: String
        let amount: Double
        @Binding var isExpanded: Bool
        @ViewBuilder var expandedContent: () -> Expanded

        var body: some View {
            VStack(spacing: 8) {
                HStack {
                    Text(title)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(Preview.isActive ? nil : .easeInOut(duration: 0.2), value: isExpanded)
                        .padding(.leading, 6)

                    Spacer()

                    Text(String(format: "$%.2f", amount))
                        .font(.subheadline.weight(.semibold))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // Do not animate layout height
                    withAnimation(nil) {
                        isExpanded.toggle()
                    }
                }

                if isExpanded {
                    expandedContent()
                        .padding(.top, 4)
                }
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
            .padding(.horizontal, 12)
            .transaction { txn in
                txn.disablesAnimations = true
            }
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

    // New: per-tile breakdown toggles
    @Binding var showGroundBreakdown: Bool
    @Binding var showSecondBreakdown: Bool
    @Binding var showThreePlusBreakdown: Bool
    @Binding var showBasementBreakdown: Bool

    let nearBottom: Bool
    let barHeight: CGFloat

    // Advanced modifiers per tile
    @Binding var groundModifiers: [AdvancedModifierItem]
    @Binding var secondModifiers: [AdvancedModifierItem]
    @Binding var threePlusModifiers: [AdvancedModifierItem]
    @Binding var basementModifiers: [AdvancedModifierItem]

    // New: bottom itemization values (computed by parent)
    let baseSubtotal: Double
    let modifiersSubtotal: Double

    // Freeze binding from parent
    @Binding var isScrollFrozen: Bool

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
                    // breakdown toggles
                    showGroundBreakdown: $showGroundBreakdown,
                    showSecondBreakdown: $showSecondBreakdown,
                    showThreePlusBreakdown: $showThreePlusBreakdown,
                    showBasementBreakdown: $showBasementBreakdown,
                    groundModifiers: $groundModifiers,
                    secondModifiers: $secondModifiers,
                    threePlusModifiers: $threePlusModifiers,
                    basementModifiers: $basementModifiers,
                    isScrollFrozen: $isScrollFrozen
                )

                // Bottom itemization section
                BottomItemizationView(
                    baseSubtotal: baseSubtotal,
                    modifiersSubtotal: modifiersSubtotal,
                    groundCount: groundCount,
                    secondCount: secondCount,
                    threePlusCount: threePlusCount,
                    basementCount: basementCount,
                    groundPrice: groundPrice,
                    secondPrice: secondPrice,
                    threePlusPrice: threePlusPrice,
                    basementPrice: basementPrice,
                    groundModifiers: groundModifiers,
                    secondModifiers: secondModifiers,
                    threePlusModifiers: threePlusModifiers,
                    basementModifiers: basementModifiers
                )
                .padding(.top, 8)

                // Always reserve space for the overlay bar to avoid layout shifts.
                Spacer().frame(height: barHeight + 12)
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
        // Allow interactive drag to dismiss keyboard, reducing focus-induced scroll adjustments
        .scrollDismissesKeyboard(.interactively)
        .scrollDisabled(isScrollFrozen)
        .coordinateSpace(name: "ScrollArea")
        .onPreferenceChange(ScrollMetricsPreferenceKey.self) { metrics in
            if let ch = metrics.contentHeight {
                onContentHeightChanged(ch)
            }
        }
        .transaction { txn in
            txn.disablesAnimations = true
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

    // New: per-tile breakdown toggles
    @Binding var showGroundBreakdown: Bool
    @Binding var showSecondBreakdown: Bool
    @Binding var showThreePlusBreakdown: Bool
    @Binding var showBasementBreakdown: Bool

    // Advanced modifiers per tile
    @Binding var groundModifiers: [AdvancedModifierItem]
    @Binding var secondModifiers: [AdvancedModifierItem]
    @Binding var threePlusModifiers: [AdvancedModifierItem]
    @Binding var basementModifiers: [AdvancedModifierItem]

    // Freeze binding propagated down
    @Binding var isScrollFrozen: Bool

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
                    modifiers: $groundModifiers,
                    showBreakdown: $showGroundBreakdown
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
                    modifiers: $secondModifiers,
                    showBreakdown: $showSecondBreakdown
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
                    modifiers: $threePlusModifiers,
                    showBreakdown: $showThreePlusBreakdown
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
                    modifiers: $basementModifiers,
                    showBreakdown: $showBasementBreakdown
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
        modifiers: Binding<[AdvancedModifierItem]>,
        showBreakdown: Binding<Bool>
    ) -> some View {
        let collapsedHeight: CGFloat = 320

        // Precompute totals
        let total = tileTotal(
            count: count.wrappedValue,
            basePrice: price.wrappedValue,
            modifiers: modifiers.wrappedValue
        )

        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: Alignment.center)
            .multilineTextAlignment(.center)

            CountControlsRow(count: count)

            VStack(alignment: .leading, spacing: 6) {
                // Pass isScrollFrozen down to PricePerRow
                PricePerRow(isUnitMenuOpen: isUnitMenuOpen, price: price, isScrollFrozen: $isScrollFrozen)

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
                }

                HStack(spacing: 6) {
                    Text("Current total:")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(String(format: "$%.2f", total))
                        .font(.headline.weight(.semibold))
                        .kerning(-0.1)
                }
                .padding(.top, 2)

                // Breakdown toggle
                Button {
                    FreezeScroll.perform(in: "ScrollArea", isFrozen: $isScrollFrozen) {
                        showBreakdown.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(showBreakdown.wrappedValue ? "Hide breakdown" : "Show breakdown")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showBreakdown.wrappedValue ? 180 : 0))
                            .animation(Preview.isActive ? nil : .easeInOut(duration: 0.2), value: showBreakdown.wrappedValue)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if showBreakdown.wrappedValue {
                    TileBreakdownView(
                        count: count.wrappedValue,
                        basePrice: price.wrappedValue,
                        modifiers: modifiers.wrappedValue
                    )
                }
            }
            .padding(.vertical, 4)

            if !isExpanded.wrappedValue {
                Spacer(minLength: 8)
            }

            Button {
                FreezeScroll.perform(in: "ScrollArea", isFrozen: $isScrollFrozen) {
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
                AdvancedOptionsBlock(
                    modifiers: modifiers,
                    tileCount: count,
                    basePrice: price
                )
                .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: collapsedHeight,
            maxHeight: (isExpanded.wrappedValue || isUnitMenuOpen.wrappedValue) ? nil : collapsedHeight,
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
        // Ensure no implicit animation on height changes for this tile
        .transaction { txn in
            txn.disablesAnimations = true
        }
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
        @Binding var isScrollFrozen: Bool

        init(isUnitMenuOpen: Binding<Bool>, price: Binding<Double>, isScrollFrozen: Binding<Bool>) {
            self._isUnitMenuOpen = isUnitMenuOpen
            self._price = price
            self._isScrollFrozen = isScrollFrozen
        }

        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    // Freeze scroll while toggling the unit menu
                    FreezeScroll.perform(in: "ScrollArea", isFrozen: $isScrollFrozen) {
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

    // Per-tile breakdown view
    private struct TileBreakdownView: View {
        let count: Int
        let basePrice: Double
        let modifiers: [AdvancedModifierItem]

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                let safeBase = max(0, basePrice)
                let base = Double(max(0, count)) * safeBase

                HStack {
                    Text("Base:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(count) × \(currency(safeBase)) = \(currency(base))")
                }
                .font(.footnote)

                ForEach(modifiers) { mod in
                    guard mod.quantity > 0 else { return AnyView(EmptyView()) }
                    if mod.mode == .price, mod.priceValue >= 0 {
                        let qty = Double(min(mod.quantity, count))
                        let add = qty * mod.priceValue
                        return AnyView(
                            HStack {
                                Text("\(mod.name):")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(qty)) × \(currency(mod.priceValue)) = \(currency(add))")
                            }
                            .font(.footnote)
                        )
                    } else if mod.mode == .multiplier, mod.multiplierValue >= 0 {
                        let qty = Double(min(mod.quantity, count))
                        let delta = max(0, mod.multiplierValue - 1.0)
                        let add = qty * safeBase * delta
                        return AnyView(
                            HStack {
                                Text("\(mod.name):")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(qty)) × \(currency(safeBase)) × (x\(trim(mult: mod.multiplierValue)) − 1) = \(currency(add))")
                            }
                            .font(.footnote)
                        )
                    } else {
                        return AnyView(EmptyView())
                    }
                }

                let total = tileTotal(count: count, basePrice: basePrice, modifiers: modifiers)
                Divider().padding(.vertical, 4)
                HStack {
                    Text("Subtotal:")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text(currency(total))
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
            )
        }

        private func currency(_ v: Double) -> String {
            String(format: "$%.2f", v)
        }
        private func trim(mult v: Double) -> String {
            if abs(v.rounded() - v) < 0.0001 {
                return "\(Int(v))"
            }
            return String(v)
        }
    }

    // Advanced Modifiers UI
    private struct AdvancedOptionsBlock: View {
        @Binding var modifiers: [AdvancedModifierItem]
        @Binding var tileCount: Int
        @Binding var basePrice: Double

        // Track which modifiers are expanded (collapsed by default)
        @State private var expanded: Set<UUID> = []

        init(modifiers: Binding<[AdvancedModifierItem]>, tileCount: Binding<Int>, basePrice: Binding<Double>) {
            self._modifiers = modifiers
            self._tileCount = tileCount
            self._basePrice = basePrice
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                // Preserve original insertion order (no sorting)
                ForEach(modifiers) { item in
                    if let idx = modifiers.firstIndex(where: { $0.id == item.id }) {
                        CollapsibleModifierRow(
                            item: $modifiers[idx],
                            maxAllowed: maxAllowed(for: item.id),
                            tileCount: $tileCount,
                            basePrice: $basePrice,
                            isExpanded: Binding(
                                get: { expanded.contains(item.id) },
                                set: { newVal in
                                    if newVal {
                                        expanded.insert(item.id)
                                    } else {
                                        expanded.remove(item.id)
                                    }
                                }
                            )
                        )
                    }
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
            // Disable implicit animations in this subtree to avoid scroll nudges on size changes.
            .transaction { txn in
                txn.disablesAnimations = true
            }
            .onChange(of: tileCount) { _, _ in
                // Clamp any quantities that exceed new tileCount
                for i in modifiers.indices {
                    if modifiers[i].quantity > tileCount {
                        modifiers[i].quantity = tileCount
                    }
                    if modifiers[i].quantity < 0 {
                        modifiers[i].quantity = 0
                    }
                }
            }
        }

        // New per-modifier cap: each modifier can go up to the full tileCount
        private func maxAllowed(for itemID: UUID) -> Int {
            return max(0, tileCount)
        }

        private func addCustom() {
            // Create a unique default name like "Custom 2", "Custom 3", ...
            let existingCustoms = modifiers.filter { $0.isCustom }
            let nextIndex = existingCustoms.count + 1
            let defaultName = existingCustoms.isEmpty ? "Custom" : "Custom \(nextIndex)"

            // Defer to next runloop tick and disable implicit animation to avoid Canvas thrash.
            DispatchQueue.main.async {
                Preview.disableAnimations {
                    let new = AdvancedModifierItem(name: defaultName, isCustom: true)
                    modifiers.append(new)
                    // Start collapsed by default (do nothing to expanded set)
                }
            }
        }

        // Collapsible row wrapper around the previous ModifierRow content
        private struct CollapsibleModifierRow: View {
            @Binding var item: AdvancedModifierItem
            let maxAllowed: Int

            @Binding var tileCount: Int
            @Binding var basePrice: Double

            @Binding var isExpanded: Bool

            // Local text fields for inputs
            @State private var priceText: String = ""
            @State private var multiplierText: String = ""

            var body: some View {
                // Determine highlight state: collapsed and has quantity
                let hasSelection = item.quantity > 0
                let isCollapsed = !isExpanded
                let highlight = hasSelection && isCollapsed

                VStack(spacing: 0) {
                    // Header (collapsed appearance inside the same bubble)
                    Button {
                        // Toggle without layout animation
                        withAnimation(nil) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            if item.isCustom {
                                Text(item.name.isEmpty ? "Custom" : item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(Preview.isActive ? nil : .easeInOut(duration: 0.2), value: isExpanded)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, isExpanded ? 10 : 8) // a bit tighter when collapsed
                        .contentShape(Rectangle())
                        .foregroundStyle(highlight ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Divider().padding(.horizontal, 12)

                        // Expanded editor content within same bubble
                        VStack(alignment: .leading, spacing: 10) {
                            // Editable name if custom
                            if item.isCustom {
                                TextField("Custom name", text: $item.name)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline.weight(.semibold))
                            }

                            // Mode selector
                            Picker("", selection: $item.mode) {
                                Text("Add $").tag(AdvancedModifierMode.price)
                                Text("Multiply").tag(AdvancedModifierMode.multiplier)
                            }
                            .pickerStyle(.segmented)

                            // Quantity chooser with max constraint
                            QuantityControlsRow(quantity: $item.quantity, maxAllowed: maxAllowed)

                            // Input field based on mode
                            VStack(alignment: .leading, spacing: 4) {
                                if item.mode == .price {
                                    HStack(spacing: 6) {
                                        Text("Add")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        PriceInput(value: $item.priceValue, text: $priceText)
                                        Text("each")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }
                                } else {
                                    HStack(spacing: 6) {
                                        Text("Multiply by")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        MultiplierInput(value: $item.multiplierValue, text: $multiplierText)
                                        Text("each")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }

                                    // Helper delta percent
                                    let deltaPct = max(0, item.multiplierValue - 1.0) * 100.0
                                    Text(String(format: "Adds +%.0f%% of base per window", deltaPct))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // Live contribution preview
                            if item.quantity > 0 {
                                let qty = Double(min(item.quantity, tileCount))
                                if item.mode == .price {
                                    let add = qty * max(0, item.priceValue)
                                    ContributionLine(label: "Adds", amount: add)
                                } else {
                                    let delta = max(0, item.multiplierValue - 1.0)
                                    let add = qty * max(0, basePrice) * delta
                                    ContributionLine(label: "Adds", amount: add)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
                // Single bubble background that wraps both collapsed and expanded states
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(highlight ? Color.blue : Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(highlight ? Color.blue : Color(.separator), lineWidth: 0.5)
                )
                .padding(.vertical, 4)
                .transaction { txn in
                    txn.disablesAnimations = true
                }
            }

            private struct ContributionLine: View {
                let label: String
                let amount: Double

                var body: some View {
                    HStack {
                        Text(label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", amount))
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.footnote)
                }
            }

            // MARK: - Localized quantity controls (match tile styling)
            private struct QuantityControlsRow: View {
                @Binding var quantity: Int
                let maxAllowed: Int

                init(quantity: Binding<Int>, maxAllowed: Int) {
                    _quantity = quantity
                    self.maxAllowed = maxAllowed
                }

                var body: some View {
                    HStack(spacing: 12) {
                        Button {
                            if quantity > 0 {
                                quantity -= 1
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 36)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
                        }
                        .disabled(quantity == 0)

                        EditableCountField(count: $quantity, maxAllowed: maxAllowed)
                            .frame(width: 60)

                        Button {
                            if quantity < maxAllowed {
                                quantity += 1
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 36)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
                        }
                        .disabled(quantity >= maxAllowed)
                    }
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Local editable numeric field with max constraint
                private struct EditableCountField: View {
                    @Binding var count: Int
                    let maxAllowed: Int

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
                                    count = min(max(0, val), maxAllowed)
                                } else if digits.isEmpty {
                                    count = 0
                                }
                            }
                        ))
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .frame(minWidth: 50)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemBackground))
                        )
                        .onAppear {
                            text = String(count)
                        }
                        .onChange(of: count) { _, newValue in
                            let clamped = min(max(0, newValue), maxAllowed)
                            if clamped != count {
                                count = clamped
                            }
                            let current = Int(text) ?? 0
                            if current != clamped {
                                text = String(clamped)
                            }
                        }
                        .accessibilityLabel("Quantity")
                    }
                }
            }

            // Reuse static helpers from the original ModifierRow
            private struct ModifierRow {
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
                        return "x1"
                    }
                    return result
                }
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
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .onChange(of: focused) { _, f in
                        if !f {
                            text = ModifierRow.currencyString(from: value)
                        }
                    }
                    .accessibilityLabel("Modifier add price per window")
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
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .onChange(of: focused) { _, f in
                        if !f {
                            text = ModifierRow.multiplierString(from: value)
                        }
                    }
                    .accessibilityLabel("Modifier multiplier per window")
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

// MARK: - Shared tile total calculator applying advanced modifiers (file scope)

// New additive model: base + sum(price lines) + sum(multiplier deltas)
fileprivate func tileTotal(count: Int, basePrice: Double, modifiers: [AdvancedModifierItem]) -> Double {
    guard count > 0, basePrice >= 0 else {
        return 0
    }

    let safeBase = max(0, basePrice)
    let base = Double(count) * safeBase

    // Split map/reduce to avoid parser/typing ambiguity
    let priceLineValues: [Double] = modifiers
        .filter { $0.mode == .price && $0.quantity > 0 && $0.priceValue >= 0 }
        .map { Double(min($0.quantity, count)) * $0.priceValue }
    let priceAdds: Double = priceLineValues.reduce(0.0, +)

    let multiplierLineValues: [Double] = modifiers
        .filter { $0.mode == .multiplier && $0.quantity > 0 && $0.multiplierValue >= 0 }
        .map { mod in
            let qty = Double(min(mod.quantity, count))
            let delta = max(0, mod.multiplierValue - 1.0) // only add extra above base
            return qty * safeBase * delta
        }
    let multiplierAdds: Double = multiplierLineValues.reduce(0.0, +)

    return base + priceAdds + multiplierAdds
}

#Preview {
    NavigationStack {
        // Use mock provider so Canvas never touches MapKit/CoreLocation
        EstimatorMainView(source: .standard, suggestionProvider: MockSuggestionProvider())
            .environmentObject(EstimatorStore())
    }
}
