//
//  UndoBanner.swift
//  balledback
//
//  Created by James Perrow on 10/16/25.
//

import SwiftUI

struct UndoBanner: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.white)
            Text(title)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button("Undo") {
                onUndo()
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
