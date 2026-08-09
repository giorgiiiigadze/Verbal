//
//  MarqueeText.swift
//  Verbal
//
//  A single-line label that scrolls its text horizontally, on a gentle
//  continuous loop, when the text is wider than the space it's given.
//  Short text that fits is rendered static (no pointless motion).
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .headline
    var color: Color = Color(.mainText)
    /// Gap between the repeated copies while scrolling.
    var gap: CGFloat = 44
    /// Scroll speed in points per second.
    var pointsPerSecond: CGFloat = 28
    /// Width of the soft fade at each edge. The text is inset by this much so the
    /// first glyph never sits underneath the leading fade.
    var fadeWidth: CGFloat = 14
    /// Beat of stillness at the start of every loop, so the beginning is readable
    /// before it slides away.
    var startDelay: Double = 1.2

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var isOverflowing: Bool { textWidth > containerWidth + 0.5 }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            // Measure the width we have to work with.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { containerWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, w in containerWidth = w }
                }
            )
            // Measure the text's natural width (hidden probe).
            .background(
                label
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { textWidth = proxy.size.width }
                                .onChange(of: text) { _, _ in textWidth = proxy.size.width }
                        }
                    )
            )
    }

    @ViewBuilder
    private var content: some View {
        if isOverflowing {
            scrolling
        } else {
            label
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var scrolling: some View {
        let distance = textWidth + gap
        let duration = Double(distance / max(pointsPerSecond, 1))
        // Two phases: rest at the start, then travel one full copy-plus-gap. Because
        // the second copy lands exactly where the first began, snapping back to the
        // resting phase is invisible — which is what makes the loop seamless.
        return PhaseAnimator([false, true]) { scrolled in
            HStack(spacing: gap) {
                label.fixedSize()
                label.fixedSize()
            }
            .offset(x: scrolled ? -distance : 0)
            .padding(.leading, fadeWidth)
            .frame(width: containerWidth, alignment: .leading)
        } animation: { scrolled in
            scrolled ? .linear(duration: duration).delay(startDelay)
                     : .linear(duration: 0)
        }
        .clipped()
        .mask(edgeFade)
        // Restart the loop cleanly if the text (and thus distance) changes.
        .id(text)
    }

    /// Soft fade at both edges so text slides in/out instead of hard-clipping.
    /// Sized in points rather than percent, so the fade stays consistent whatever
    /// width the label is given.
    private var edgeFade: some View {
        let width = max(containerWidth, 1)
        let lead = min(fadeWidth / width, 0.5)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: lead),
                .init(color: .black, location: 1 - lead),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
