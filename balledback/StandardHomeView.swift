//
//  StandardHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI
import UIKit

struct StandardHomeView: View {
    @State private var goToEstimator = false
    @EnvironmentObject private var store: EstimatorStore

    // Undo state
    @State private var recentlyDeleted: Estimate?
    @State private var recentlyDeletedIndex: Int?
    @State private var showUndoBanner = false
    @State private var undoTimer: Timer?

    // Delete animation state
    @State private var deletingID: UUID?
    @State private var prePopID: UUID? // for tiny overshoot before pop

    // Compute 5 most recent standard estimates
    private var recentStandardEstimates: [Estimate] {
        store.standardEstimates
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if store.standardEstimates.isEmpty {
                    // Empty state keeps your previous padding/layout feel
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("No saved estimates yet.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } else {
                    // Use List to enable native swipe-to-delete
                    List {
                        Section("Recent Estimates") {
                            ForEach(recentStandardEstimates) { estimate in
                                NavigationLink {
                                    EstimatorMainView(source: .standard, existingEstimate: estimate)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(estimate.jobName)
                                                .font(.subheadline.weight(.semibold))
                                            if !estimate.jobLocation.isEmpty {
                                                Text(estimate.jobLocation)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !estimate.phoneNumber.isEmpty {
                                                Text(estimate.phoneNumber)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()

                                        // Status bubble (placeholder)
                                        Text("Status")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule().fill(Color.blue.opacity(0.12))
                                            )
                                            .overlay(
                                                Capsule().stroke(Color.blue.opacity(0.35), lineWidth: 0.5)
                                            )

                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    // Dramatic pop animation
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

                                        // Tiny overshoot, then dramatic pop
                                        prePopID = estimate.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                            prePopID = nil
                                            deletingID = estimate.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                                deleteWithUndo(estimate)
                                                // Reset deletingID shortly after
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
            .padding(20)
            .accessibilityLabel("Add")

            // Undo banner overlay above the FAB
            if showUndoBanner, let deleted = recentlyDeleted {
                UndoBanner(
                    title: "Deleted “\(deleted.jobName.isEmpty ? "Estimate" : deleted.jobName)”",
                    onUndo: { performUndo() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 92) // keep clear of the FAB
                .padding(.horizontal, 16)
            }
        }
        .animation(.spring(duration: 0.35), value: showUndoBanner)
        .navigationTitle("Standard")
        .navigationDestination(isPresented: $goToEstimator) {
            EstimatorMainView(source: .standard)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Standard-specific settings will go here in the future
                    Button("More settings to come") {}
                        .disabled(true)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .accessibilityLabel("Settings")
                }
            }
        }
        .onDisappear {
            invalidateUndoTimer()
        }
    }

    // MARK: - Undo Helpers

    private func deleteWithUndo(_ estimate: Estimate) {
        // Capture original index to support precise reinsertion
        if let idx = store.standardEstimates.firstIndex(where: { $0.id == estimate.id }) {
            recentlyDeletedIndex = idx
        } else {
            recentlyDeletedIndex = nil
        }

        recentlyDeleted = estimate

        // Perform deletion
        store.remove(id: estimate.id, from: .standard)

        // Show banner and start/reset timer
        showUndoBanner = true
        restartUndoTimer()
    }

    private func performUndo() {
        guard let estimate = recentlyDeleted else { return }

        // Reinsert at original index if possible; else append
        if let idx = recentlyDeletedIndex, idx <= store.standardEstimates.count {
            store.insert(estimate, at: idx, for: .standard)
        } else {
            store.append(estimate, for: .standard)
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
        // Show for ~4 seconds
        undoTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            clearUndoState(animated: true)
        }
        // Ensure timer continues during scrolling
        RunLoop.main.add(undoTimer!, forMode: .common)
    }

    private func invalidateUndoTimer() {
        undoTimer?.invalidate()
        undoTimer = nil
    }
}

#Preview {
    NavigationStack { StandardHomeView().environmentObject(EstimatorStore()) }
}
