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

    // Search text (non-functional placeholder for now)
    @State private var searchText: String = ""

    // Navigation triggers for tiles
    @State private var showFavorites = false
    @State private var showDrafts = false
    @State private var showCompleted = false
    @State private var showDeleted = false
    @State private var showScheduled = false
    @State private var showAll = false

    // Compute 5 most recent premium estimates (same logic as dashboard)
    private var recentPremiumEstimates: [Estimate] {
        store.premiumEstimates
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(5)
            .map { $0 }
    }

    // Counts for tiles
    private var favoritesCount: Int {
        store.premiumEstimates.filter { $0.isFavorite }.count
    }
    private var draftsCount: Int { 0 }      // placeholder until we define drafts
    private var completedCount: Int { 0 }   // placeholder until we add isCompleted
    private var deletedCount: Int { 0 }     // placeholder until we add trash model
    private var scheduledCount: Int { 0 }   // placeholder until we source from scheduledJobs
    private var allCount: Int { store.premiumEstimates.count }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Always use a List so the sections are rigidly present
            List {
                // Header search box above the sections
                Section {
                    SearchBox(text: $searchText)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                // NEW: Status Tiles section (horizontal scrolling)
                Section("Status") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            StatusTile(
                                title: "Favorites",
                                systemImage: "star.fill",
                                count: favoritesCount,
                                tint: .yellow
                            ) { showFavorites = true }

                            StatusTile(
                                title: "Saved",
                                systemImage: "bookmark.fill",
                                count: draftsCount,
                                tint: .blue
                            ) { showDrafts = true }

                            StatusTile(
                                title: "Completed",
                                systemImage: "checkmark.circle.fill",
                                count: completedCount,
                                tint: .green
                            ) { showCompleted = true }

                            StatusTile(
                                title: "Deleted",
                                systemImage: "trash.fill",
                                count: deletedCount,
                                tint: .red
                            ) { showDeleted = true }

                            StatusTile(
                                title: "Scheduled",
                                systemImage: "calendar.badge.clock",
                                count: scheduledCount,
                                tint: .purple
                            ) { showScheduled = true }

                            StatusTile(
                                title: "All",
                                systemImage: "list.bullet.rectangle",
                                count: allCount,
                                tint: .teal
                            ) { showAll = true }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                }

                // Rigid Recent Estimates section: always present
                Section("Recent Estimates") {
                    if recentPremiumEstimates.isEmpty {
                        // Placeholder row when none
                        HStack {
                            Text("No recent estimates yet.")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    } else {
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
            }
            .listStyle(.insetGrouped)

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
        // Navigation destinations for tiles
        .navigationDestination(isPresented: $showFavorites) {
            FavoritesListView().environmentObject(store)
        }
        .navigationDestination(isPresented: $showDrafts) {
            DraftsListView().environmentObject(store)
        }
        .navigationDestination(isPresented: $showCompleted) {
            CompletedListView().environmentObject(store)
        }
        .navigationDestination(isPresented: $showDeleted) {
            DeletedListView().environmentObject(store)
        }
        .navigationDestination(isPresented: $showScheduled) {
            ScheduledListView().environmentObject(store)
        }
        .navigationDestination(isPresented: $showAll) {
            AllEstimatesListView().environmentObject(store)
        }
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

// MARK: - Search box (non-functional placeholder)
private struct SearchBox: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            TextField("Search quotes", text: $text)
                .textInputAutocapitalization(.none)
                .autocorrectionDisabled(true)
                .submitLabel(.search)

            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}

// MARK: - Status Tile
private struct StatusTile: View {
    let title: String
    let systemImage: String
    let count: Int
    let tint: Color
    let action: () -> Void

    // Fixed width so ~2.5 tiles are visible on typical phones
    private let tileWidth: CGFloat = 180

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(count)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: tileWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Destination list views

private struct FavoritesListView: View {
    @EnvironmentObject private var store: EstimatorStore

    private var favorites: [Estimate] {
        store.premiumEstimates.filter { $0.isFavorite }
            .sorted(by: { $0.createdAt > $1.createdAt })
    }

    var body: some View {
        List {
            Section("Favorites") {
                if favorites.isEmpty {
                    Text("No favorites yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(favorites) { estimate in
                        EstimateRow(estimate: estimate)
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        .listStyle(.insetGrouped)
    }
}

private struct DraftsListView: View {
    var body: some View {
        List {
            Section("Saved") {
                Text("No saved drafts yet.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved")
        .listStyle(.insetGrouped)
    }
}

private struct CompletedListView: View {
    var body: some View {
        List {
            Section("Completed") {
                Text("No completed jobs yet.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Completed")
        .listStyle(.insetGrouped)
    }
}

private struct DeletedListView: View {
    var body: some View {
        List {
            Section("Deleted") {
                Text("No deleted items.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Deleted")
        .listStyle(.insetGrouped)
    }
}

private struct ScheduledListView: View {
    var body: some View {
        List {
            Section("Scheduled") {
                Text("No scheduled jobs yet.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Scheduled")
        .listStyle(.insetGrouped)
    }
}

private struct AllEstimatesListView: View {
    @EnvironmentObject private var store: EstimatorStore

    private var all: [Estimate] {
        store.premiumEstimates.sorted(by: { $0.createdAt > $1.createdAt })
    }

    var body: some View {
        List {
            Section("All Estimates") {
                if all.isEmpty {
                    Text("No estimates yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(all) { estimate in
                        EstimateRow(estimate: estimate)
                    }
                }
            }
        }
        .navigationTitle("All")
        .listStyle(.insetGrouped)
    }
}

// Shared simple row presentation for list views
private struct EstimateRow: View {
    let estimate: Estimate

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(estimate.jobName).font(.subheadline.weight(.semibold))
                if !estimate.jobLocation.isEmpty {
                    Text(estimate.jobLocation).foregroundStyle(.secondary)
                }
                if !estimate.phoneNumber.isEmpty {
                    Text(estimate.phoneNumber).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if estimate.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        QuotesHomeView()
            .environmentObject(PremiumRouter())
            .environmentObject(EstimatorStore())
    }
}
