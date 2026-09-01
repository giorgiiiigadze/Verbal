//
//  LevelTrace.swift
//  Verbal
//
//  What the microphone is hearing, as a trace of the last few seconds.
//

import SwiftUI

/// A running trace of microphone level, oldest bar on the left.
///
/// A history rather than a single bar: one bar rising and falling says the
/// microphone is open, a trace says what was just said, which is the thing
/// somebody speaking a job into a phone actually wants to see.
///
/// Silence draws a flat line rather than nothing, because silence is a real
/// answer — a meter that empties out looks like one that stopped working.
struct LevelTrace: View {
    static let barCount = 26
    let levels: [Float]
    var color: Color = Color(.blueAccentText)

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(opacity(at: index)))
                    .frame(width: 3, height: height(at: index))
            }
        }
    }

    /// The history is right-aligned, so a trace that has only just started grows
    /// in from the right rather than sitting oddly on the left.
    private func level(at index: Int) -> CGFloat {
        let offset = Self.barCount - levels.count
        guard index >= offset, index - offset < levels.count else { return 0 }
        return CGFloat(levels[index - offset])
    }

    private func height(at index: Int) -> CGFloat {
        3 + level(at: index) * 19
    }

    /// Older bars fade, so the newest end reads as the live one.
    private func opacity(at index: Int) -> Double {
        let age = Double(Self.barCount - index) / Double(Self.barCount)
        return 0.25 + (1 - age) * 0.6
    }
}
