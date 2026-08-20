//
//  OfflineBanner.swift
//  Verbal
//
//  Native liquid-glass toast shown briefly at the top of the signed-in app when
//  the device loses its network connection.
//

import SwiftUI

struct OfflineBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(.mainText))

            Text("No internet connection")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
