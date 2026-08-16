//
//  RollingAmount.swift
//  Verbal
//
//  A currency amount that counts to its new value instead of jumping to it.
//
//  Used where money changes because the user changed it — the quote's total and
//  each line's amount. Motion there says the edit landed and this is what it did
//  to the number, which is the whole reason anyone opens a quote after making
//  one.
//
//  Not used where a figure changes on its own. The running total inside the
//  line-items sheet recomputes on every keystroke, and digits rolling under the
//  thumb while a four-figure price is being typed read as lag rather than as
//  care.
//

import SwiftUI

struct RollingAmount: View {
    let value: Double
    /// Currency the amount is priced in, so a converted quote reads in its new
    /// symbol as the digits move. Optional to match `AppCurrency.format`, which
    /// falls back to the current setting — a line on a quote that hasn't been
    /// saved yet has no currency of its own.
    let code: String?

    /// The figure actually on screen, trailing `value`.
    ///
    /// Nil until the first one arrives, which is what keeps the amount from
    /// counting up from zero every time a quote is opened. Home's band does
    /// roll from zero, and should: its figure comes from a conversion that is
    /// still running, so the count-up is the work happening. A quote's total is
    /// known the instant the screen appears, and a flourish on every open is a
    /// flourish by the third one.
    @State private var shown: Double?

    var body: some View {
        Text(AppCurrency.format(shown ?? value, code: code))
            .contentTransition(.numericText(value: shown ?? value))
            .onChange(of: value, initial: true) { _, new in
                guard shown != nil else {
                    shown = new
                    return
                }
                withAnimation(.snappy(duration: 0.45)) { shown = new }
            }
    }
}
