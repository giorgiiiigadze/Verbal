//
//  AuthBackground.swift
//  Verbal
//
//  The sign-in screen's backdrop.
//
//  Drawn rather than photographed. A picture of a kitchen mid-refit would be
//  borrowed atmosphere — it ages, it weighs, and it has to be fought into
//  behaving in dark mode. The brand mark is already a waveform, so the same
//  line carried across the screen says "this app listens" in the app's own
//  language, stays sharp at any size, and costs nothing to ship.
//

import SwiftUI

struct AuthBackground: View {
    @Environment(\.colorScheme) private var scheme

    /// The waves are drawn in the action blue, which has no dark variant —
    /// #1D5DE6 over a #1C1C1E background is dark blue on near-black, so at
    /// these opacities the whole drawing simply wasn't there. In dark mode they
    /// invert to white, which is the same gesture read the other way round.
    ///
    /// The opacities carry over unchanged: white at 10% over the dark ground
    /// lands about as far from it as the navy does from the light one, so the
    /// lines stay as quiet in one appearance as the other.
    private var lineColor: Color {
        scheme == .dark ? .white : Color(.royalBlue600)
    }

    var body: some View {
        ZStack {
            Color(.homeBackground)

            // Tint gathers at the top, where the lockup and headline sit, and
            // clears before the bottom so the sign-in button keeps plain
            // ground under it.
            LinearGradient(
                colors: [
                    Color(.royalBlue600).opacity(0.18),
                    Color(.royalBlue600).opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                ForEach(Array(Self.waves.enumerated()), id: \.offset) { _, wave in
                    Wave(amplitude: wave.amplitude,
                         wavelength: wave.wavelength,
                         phase: wave.phase)
                        .stroke(lineColor.opacity(wave.opacity),
                                style: StrokeStyle(lineWidth: wave.width, lineCap: .round))
                        .frame(height: 220)
                        .position(x: proxy.size.width / 2,
                                  y: proxy.size.height * wave.y)
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// Varied on every axis so they read as one drawn gesture rather than a
    /// pattern. Weight varies most: strokes of the same thickness look printed,
    /// while a heavy line next to a light one looks drawn. Still faint enough
    /// that the type in front never has to compete.
    private static let waves: [(y: CGFloat, amplitude: CGFloat, wavelength: CGFloat,
                               phase: CGFloat, opacity: Double, width: CGFloat)] = [
        (0.14, 26, 190, 0.0, 0.10, 2.0),
        (0.26, 44, 320, 1.2, 0.07, 1.3),
        (0.40, 18, 150, 2.4, 0.06, 1.7),
        (0.58, 36, 265, 0.6, 0.05, 2.2),
        (0.74, 22, 205, 3.1, 0.04, 1.4)
    ]
}

/// A single sine sweep across the full width of its frame.
private struct Wave: Shape {
    let amplitude: CGFloat
    let wavelength: CGFloat
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX,
                              y: midY + sin(phase) * amplitude))
        var x = rect.minX
        while x <= rect.maxX {
            let y = midY + sin(x / wavelength * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        return path
    }
}
