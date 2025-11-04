// PremiumHomeContainerView.swift
import SwiftUI

struct PremiumHomeContainerView: View {
    @State private var selected: PremiumSection = .dashboard
    @EnvironmentObject private var store: EstimatorStore
    @StateObject private var router = PremiumRouter()
    @State private var path = NavigationPath()

    // Approximate visual height of the bottom bar to place floating elements above it if needed later
    private let bottomBarHeight: CGFloat = 64

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch selected {
                    case .dashboard:
                        DashboardHomeView()
                            .environmentObject(store)

                    case .quotes:
                        QuotesHomeView()

                    case .team:
                        TeamHomeView()

                    case .map:
                        MapHomeView()

                    case .customers:
                        CustomersHomeView()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                SelectionBottomActionBar(selected: $selected)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .background(.thinMaterial)
                    .overlay(
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 0.5)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )
            }
        }
        // Attach navigationDestination directly to the NavigationStack via the .navigationDestination modifier on the container
        .navigationDestination(isPresented: $router.showEstimator) {
            EstimatorMainView(
                source: .premium,
                existingEstimate: router.editingEstimate
            )
            .environmentObject(store)
        }
        // Inject router so children can request navigation
        .environmentObject(router)
    }
}

// Bottom bar that switches sections via a Binding
private struct SelectionBottomActionBar: View {
    @Binding var selected: PremiumSection

    var body: some View {
        HStack(spacing: 0) {
            barButton(.dashboard)
            Divider().frame(height: 28).opacity(0.2)
            barButton(.quotes)
            Divider().frame(height: 28).opacity(0.2)
            barButton(.team)
            Divider().frame(height: 28).opacity(0.2)
            barButton(.map)
            Divider().frame(height: 28).opacity(0.2)
            barButton(.customers)
        }
    }

    @ViewBuilder
    private func barButton(_ section: PremiumSection) -> some View {
        let isSelected = selected == section
        Button {
            selected = section
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.blue : Color.primary)
                Text(section.title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(isSelected ? Color.blue : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
