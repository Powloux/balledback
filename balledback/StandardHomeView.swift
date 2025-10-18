//
//  StandardHomeView.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct StandardHomeView: View {
    @State private var goToEstimator = false
    @EnvironmentObject private var store: EstimatorStore

    // Undo state
    @State private var recentlyDeleted: Estimate?
    @State private var recentlyDeletedIndex: Int?
    @State private var showUndoBanner = false
    @State private var undoTimer: Timer?

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
                        Section("Saved Estimates") {
                            ForEach(store.standardEstimates) { estimate in
                                NavigationLink {
                                    EstimatorMainView(source: .standard, existingEstimate: estimate)
                                } label: {
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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteWithUndo(estimate)
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
                undoBanner(for: deleted)
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

    // MARK: - Banner View

    @ViewBuilder
    private func undoBanner(for estimate: Estimate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.white)
            Text("Deleted “\(estimate.jobName.isEmpty ? "Estimate" : estimate.jobName)”")
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button("Undo") {
                performUndo()
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.white.opacity(0.2))
            )
            .accessibilityLabel("Undo delete")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack { StandardHomeView().environmentObject(EstimatorStore()) }
}
