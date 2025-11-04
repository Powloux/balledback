//
//  PremiumHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI
import UIKit

struct PremiumHomeView: View {
    @State private var goToEstimator = false
    @EnvironmentObject private var store: EstimatorStore

    // Undo state
    @State private var recentlyDeleted: Estimate?
    @State private var recentlyDeletedIndex: Int?
    @State private var showUndoBanner = false
    @State private var undoTimer: Timer?

    // Delete animation state
    @State private var deletingID: UUID?
    @State private var prePopID: UUID?

    // Account sheet
    @State private var showAccount = false

    // Set Standard Pricing sheet
    @State private var showStandardPricing = false

    // Online/Offline toggle (placeholder state for now)
    @State private var isOnline = true

    // Bottom bar height (approximate visual height incl. padding)
    private let bottomBarHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if store.premiumEstimates.isEmpty {
                    // Empty state
                    ScrollView {
                        VStack(spacing: 12) {
                            Text("Premium Home")
                                .font(.largeTitle)
                                .bold()
                            Text("This is a placeholder for the premium experience.")
                                .foregroundStyle(.secondary)

                            Text("No saved estimates yet.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding()
                    }
                } else {
                    // Use List to enable native swipe-to-delete
                    List {
                        Section("Saved Estimates") {
                            ForEach(store.premiumEstimates) { estimate in
                                NavigationLink {
                                    EstimatorMainView(source: .premium, existingEstimate: estimate)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(estimate.jobName).font(.subheadline.weight(.semibold))
                                        if !estimate.jobLocation.isEmpty {
                                            Text(estimate.jobLocation).foregroundStyle(.secondary)
                                        }
                                        if !estimate.phoneNumber.isEmpty {
                                            Text(estimate.phoneNumber).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .scaleEffect(prePopID == estimate.id ? 1.04 : (deletingID == estimate.id ? 0.65 : 1.0))
                                    .rotationEffect(.degrees(deletingID == estimate.id ? 6 : 0))
                                    .blur(radius: deletingID == estimate.id ? 2 : 0)
                                    .opacity(deletingID == estimate.id ? 0.0 : 1.0)
                                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: prePopID)
                                    .animation(.spring(response: 0.16, dampingFraction: 0.65), value: deletingID)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        // Haptic feedback
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()

                                        prePopID = estimate.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                            prePopID = nil
                                            deletingID = estimate.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                                deleteWithUndo(estimate)
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                                    deletingID = nil
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }

            // Floating action button pinned to bottom-right
            Button {
                goToEstimator = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.blue))
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            }
            .padding(.trailing, 20)
            // Lift the FAB up enough to clear the inset bottom bar
            .padding(.bottom, bottomBarHeight + 20)
            .accessibilityLabel("Add")

            // Undo banner overlay above the FAB
            if showUndoBanner, let deleted = recentlyDeleted {
                UndoBanner(
                    title: "Deleted “\(deleted.jobName.isEmpty ? "Estimate" : deleted.jobName)”",
                    onUndo: { performUndo() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                // Place above FAB and bottom bar
                .padding(.bottom, bottomBarHeight + 88)
                .padding(.horizontal, 16)
            }
        }
        .animation(.spring(duration: 0.35), value: showUndoBanner)
        .navigationTitle("Hello, User")
        .navigationDestination(isPresented: $goToEstimator) {
            EstimatorMainView(source: .premium)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Compact Online/Offline chip (slightly larger to avoid truncation)
                OnlineStatusChip(isOnline: $isOnline)

                // Account button
                Button {
                    showAccount = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .accessibilityLabel("Account")
                }

                // Settings menu restored, with "Set Standard Pricing" inside
                Menu {
                    Button("Set Standard Pricing") {
                        showStandardPricing = true
                    }
                    // Future settings can be added here
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showAccount) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Account")
                        .font(.largeTitle).bold()
                    Text("This is a placeholder for your account details and preferences.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showAccount = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showStandardPricing) {
            NavigationStack {
                SetStandardPricingView(current: store.standardPricing)
                    .environmentObject(store)
            }
        }
        // Inject the bottom action bar using safeAreaInset so it always stays at the bottom
        .safeAreaInset(edge: .bottom) {
            BottomActionBar()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8) // minimal horizontal padding to maximize width
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(.thinMaterial) // subtle background; can change to Color(.systemBackground)
                .overlay(
                    // Top divider only, to separate from content without stealing width
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                        .frame(maxHeight: .infinity, alignment: .top)
                )
        }
        .onDisappear {
            invalidateUndoTimer()
        }
    }

    // MARK: - Undo Helpers

    private func deleteWithUndo(_ estimate: Estimate) {
        if let idx = store.premiumEstimates.firstIndex(where: { $0.id == estimate.id }) {
            recentlyDeletedIndex = idx
        } else {
            recentlyDeletedIndex = nil
        }

        recentlyDeleted = estimate
        store.remove(id: estimate.id, from: .premium)
        showUndoBanner = true
        restartUndoTimer()
    }

    private func performUndo() {
        guard let estimate = recentlyDeleted else { return }
        if let idx = recentlyDeletedIndex, idx <= store.premiumEstimates.count {
            store.insert(estimate, at: idx, for: .premium)
        } else {
            store.append(estimate, for: .premium)
        }
        clearUndoState(animated: true)
    }

    private func clearUndoState(animated: Bool) {
        invalidateUndoTimer()
        if animated {
            withAnimation {
                showUndoBanner = false
            }
        } else {
            showUndoBanner = false
        }
        recentlyDeleted = nil
        recentlyDeletedIndex = nil
    }

    private func restartUndoTimer() {
        invalidateUndoTimer()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            clearUndoState(animated: true)
        }
        RunLoop.main.add(undoTimer!, forMode: .common)
    }

    private func invalidateUndoTimer() {
        undoTimer?.invalidate()
        undoTimer = nil
    }
}

// MARK: - Bottom Action Bar (5 placeholder buttons)

private struct BottomActionBar: View {
    var body: some View {
        HStack(spacing: 0) {
            // Dashboard uses a house icon now
            PlaceholderButton(title: "Dashboard", systemImage: "house.fill")
            Divider().frame(height: 28).opacity(0.2)
            PlaceholderButton(title: "Quotes", systemImage: "long.text.page.and.pencil.fill")
            Divider().frame(height: 28).opacity(0.2)
            PlaceholderButton(title: "Team", systemImage: "person.2.wave.2.fill")
            Divider().frame(height: 28).opacity(0.2)
            PlaceholderButton(title: "Map", systemImage: "map.fill")
            Divider().frame(height: 28).opacity(0.2)
            PlaceholderButton(title: "Customers", systemImage: "person.3.fill")
        }
    }

    private struct PlaceholderButton: View {
        let title: String
        let systemImage: String

        var body: some View {
            Button {
                // placeholder action
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold)) // slightly smaller icon
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2) // allow two lines
                        .minimumScaleFactor(0.85) // scale down if needed
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6) // minimal vertical padding
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
        }
    }
}

// MARK: - Compact online status chip for toolbar

private struct OnlineStatusChip: View {
    @Binding var isOnline: Bool

    var body: some View {
        Button {
            isOnline.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isOnline ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(isOnline ? "Online" : "Offline")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minWidth: 90)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                Capsule()
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOnline ? "Status: Online" : "Status: Offline")
        .accessibilityHint("Double tap to toggle online status")
    }
}

#Preview {
    NavigationStack { PremiumHomeView().environmentObject(EstimatorStore()) }
}

