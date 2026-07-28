//
//  OfflineBanner.swift
//  Verbal
//
//  Native liquid-glass banner shown at the top of the screen while the device
//  has no network connection. The app stays fully usable underneath it.
//

import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(.mainText))

            VStack(alignment: .leading, spacing: 2) {
                Text("You're Offline")
                    .font(.headline)
                    .foregroundStyle(Color(.mainText))
                Text("Network connection lost. Please try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect(in: .capsule)
        .padding(.horizontal, 16)
        // Float just above the tab bar rather than overlapping it.
        .padding(.bottom, 60)
    }
}
