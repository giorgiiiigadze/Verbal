//
//  StringTrimming.swift
//  Verbal
//
//  Blank means absent.
//
//  Every form in the app has to decide what an emptied field means before it
//  writes: a name typed and then deleted is not a name of one space, it is no
//  name. Three screens each kept their own copy of the four lines that say so.
//

import Foundation

extension String {
    /// The text with its edges trimmed, or nil when nothing is left — what a
    /// form field means when the user clears it.
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
