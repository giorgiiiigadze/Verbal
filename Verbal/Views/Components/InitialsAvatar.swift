//
//  InitialsAvatar.swift
//  Verbal
//
//  A circular avatar drawn from a name — initials on a tint picked from the
//  name itself, so a client keeps the same colour every time they appear.
//
//  Separate from AvatarView, which shows the signed-in user's own photo. This
//  one stands in for people the app has no picture of: the clients on a quote.
//

import SwiftUI

struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 40

    /// Up to two initials, e.g. "Marina Kapanadze" → "MK", "cava" → "C".
    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters = words.prefix(2).compactMap(\.first).map { String($0) }.joined()
        return letters.uppercased()
    }

    /// A stable hue in [0,1) derived from the name. Deliberately not
    /// `hashValue`, which Swift salts per launch — the colour has to survive the
    /// app being reopened, or a client would change colour every session.
    private var hue: Double {
        var h: UInt64 = 5381
        for scalar in name.lowercased().unicodeScalars {
            h = (h &* 33) &+ UInt64(scalar.value)
        }
        return Double(h % 360) / 360
    }

    var body: some View {
        Circle()
            // Soft, desaturated fill so a row of these reads as quiet variety
            // rather than a bag of highlighters — colourful enough to tell
            // people apart, muted enough to sit under the names.
            .fill(Color(hue: hue, saturation: 0.30, brightness: 0.92))
            .frame(width: size, height: size)
            .overlay {
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(Color(hue: hue, saturation: 0.55, brightness: 0.42))
                } else {
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(Color(hue: hue, saturation: 0.60, brightness: 0.38))
                }
            }
    }
}
