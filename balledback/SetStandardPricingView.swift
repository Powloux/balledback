import SwiftUI

struct SetStandardPricingView: View {
    @EnvironmentObject private var store: EstimatorStore
    @Environment(\.dismiss) private var dismiss

    @State private var workingPricing: StandardPricing

    // Initializer to copy current store value at launch
    init(current: StandardPricing) {
        _workingPricing = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section(header: Text("Set Standard Pricing").font(.largeTitle).bold()) {
                pricingRow(
                    title: "Ground Level",
                    price: $workingPricing.groundPrice,
                    unit: $workingPricing.groundUnit
                )
                pricingRow(
                    title: "Second Story",
                    price: $workingPricing.secondPrice,
                    unit: $workingPricing.secondUnit
                )
                pricingRow(
                    title: "3+ Story",
                    price: $workingPricing.threePlusPrice,
                    unit: $workingPricing.threePlusUnit
                )
                pricingRow(
                    title: "Basement",
                    price: $workingPricing.basementPrice,
                    unit: $workingPricing.basementUnit
                )
            }
        }
        .navigationTitle("Standard Pricing")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.updateStandardPricing(workingPricing)
                    dismiss()
                }
                .font(.headline)
            }
        }
    }

    @ViewBuilder
    private func pricingRow(title: String, price: Binding<Double>, unit: Binding<PricingUnit>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("$0.00", value: price, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: unit) {
                ForEach(PricingUnit.allCases) { unit in
                    Text(unit.rawValue.capitalized).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .padding(.vertical, 4)
    }
}
