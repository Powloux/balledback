import SwiftUI
import UIKit

struct DashboardHomeView: View {
    @EnvironmentObject private var store: EstimatorStore
    @EnvironmentObject private var router: PremiumRouter

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

    // Calendar selection (local state for now)
    @State private var selectedDate: Date = Date()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if store.premiumEstimates.isEmpty {
                    // Empty state
                    ScrollView {
                        VStack(spacing: 12) {
                            // Weather placeholder under the title area
                            WeatherPlaceholderCard()
                                .padding(.bottom, 8)

                            // Calendar widget under weather
                            CalendarCard(selectedDate: $selectedDate)
                                .padding(.bottom, 8)

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
                        // Weather placeholder section at the top of the dashboard
                        Section("Weather") {
                            WeatherPlaceholderCard()
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                            // Calendar widget directly under weather
                            CalendarCard(selectedDate: $selectedDate)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        }

                        Section("Saved Estimates") {
                            ForEach(store.premiumEstimates) { estimate in
                                Button {
                                    // Route edit via router so it pushes on the container’s NavigationStack
                                    router.openEdit(estimate)
                                } label: {
                                    HStack {
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
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle()) // Make entire bubble tappable
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
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
                // Place above bottom bar supplied by container
                .padding(.bottom, bottomBarHeight + 88)
                .padding(.horizontal, 16)
            }
        }
        .animation(.spring(duration: 0.35), value: showUndoBanner)
        .navigationTitle("Hello, User")
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

// Simple placeholder weather card to remind you to implement real weather later
private struct WeatherPlaceholderCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange, .yellow, .blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Weather")
                    .font(.headline)
                Text("72° • Partly Cloudy")
                    .font(.subheadline.weight(.semibold))
                Text("Forecast: High 78° / Low 62°")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather. Seventy two degrees, partly cloudy. Forecast high seventy eight, low sixty two.")
    }
}

// Calendar card widget styled like WeatherPlaceholderCard
private struct CalendarCard: View {
    @Binding var selectedDate: Date

    private var titleDateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calendar")
                    .font(.headline)
                Spacer()
                Text(titleDateFormatter.string(from: selectedDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            // Graphical calendar style (interactive)
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calendar. \(DateFormatter.localizedString(from: selectedDate, dateStyle: .long, timeStyle: .none)) selected.")
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
    NavigationStack { DashboardHomeView().environmentObject(EstimatorStore()) }
}
