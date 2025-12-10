// QuotesHomeView.swift
import SwiftUI

struct QuotesHomeView: View {
    @EnvironmentObject private var router: PremiumRouter
    @EnvironmentObject private var store: EstimatorStore

    // Approximate visual height of the bottom bar to keep the FAB above it, matching Dashboard
    private let bottomBarHeight: CGFloat = 64

    // Undo state
    @State private var recentlyDeleted: Estimate?
    @State private var recentlyDeletedIndex: Int?
    @State private var showUndoBanner = false
    @State private var undoTimer: Timer?

    // Delete animation state (match dashboard feel)
    @State private var deletingID: UUID?
    @State private var prePopID: UUID?

    // Compute 5 most recent premium estimates (same logic as dashboard)
    private var recentPremiumEstimates: [Estimate] {
        store.premiumEstimates
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if store.premiumEstimates.isEmpty {
                    // Keep an empty ScrollView to preserve structure and future content space
                    ScrollView {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding()
                    }
                } else {
                    // Mirror dashboard: show recent estimates limited to 5 with swipe-to-delete
                    List {
                        Section("Recent Estimates") {
                            ForEach(recentPremiumEstimates) { estimate in
                                Button {
                                    router.openEdit(estimate)
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

                                        // Favorite star (same as dashboard)
                                        Button {
                                            var updated = estimate
                                            updated.isFavorite.toggle()
                                            store.update(id: estimate.id, with: updated, from: .premium)
                                        } label: {
                                            Image(systemName: estimate.isFavorite ? "star.fill" : "star")
                                                .foregroundStyle(estimate.isFavorite ? Color.yellow : Color.secondary)
                                        }
                                        .buttonStyle(.plain)

                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 6)
                                    // Match dashboard delete animation
                                    .scaleEffect(prePopID == estimate.id ? 1.04 : (deletingID == estimate.id ? 0.65 : 1.0))
                                    .rotationEffect(.degrees(deletingID == estimate.id ? 6 : 0))
                                    .blur(radius: deletingID == estimate.id ? 2 : 0)
                                    .opacity(deletingID == estimate.id ? 0.0 : 1.0)
                                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: prePopID)
                                    .animation(.spring(response: 0.16, dampingFraction: 0.65), value: deletingID)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        // Tiny overshoot, then dramatic pop (same as dashboard)
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

            // Floating + button, same styling/placement as Dashboard
            Button {
                router.openNewEstimate()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.blue))
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            }
            .padding(.trailing, 20)
            .padding(.bottom, bottomBarHeight + 20)
            .accessibilityLabel("Add")

            // Undo banner overlay above the bottom bar (same offset pattern as dashboard)
            if showUndoBanner, let deleted = recentlyDeleted {
                UndoBanner(
                    title: "Deleted “\(deleted.jobName.isEmpty ? "Estimate" : deleted.jobName)”",
                    onUndo: { performUndo() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, bottomBarHeight + 88)
                .padding(.horizontal, 16)
            }
        }
        .animation(.spring(duration: 0.35), value: showUndoBanner)
        .navigationTitle("Quotes")
        .onDisappear {
            invalidateUndoTimer()
        }
    }

    // MARK: - Undo Helpers

    private func deleteWithUndo(_ estimate: Estimate) {
        // Capture original index from the full premiumEstimates array
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
        // Show for ~4 seconds
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

#Preview {
    NavigationStack {
        QuotesHomeView()
            .environmentObject(PremiumRouter())
            .environmentObject(EstimatorStore())
    }
}
