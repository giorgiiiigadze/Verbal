//
//  BusinessPrompt.swift
//  Verbal
//
//  Whether the share flow should stop to collect business details first.
//
//  A rule about the account rather than a part of the sheet that asks: both the
//  quote screen and Home consult it before sharing.
//

import Foundation

/// Whether the share flow should stop to collect business details first.
enum BusinessPrompt {
    private static let askedKey = "hasPromptedBusinessDetails"

    /// True when nothing identifies the business yet and we haven't already
    /// asked. Asked once per install — a second nag would just be in the way.
    static func shouldAsk(_ profile: BusinessProfile?) -> Bool {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return false }
        let name = profile?.businessName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
    }

    static func markAsked() {
        UserDefaults.standard.set(true, forKey: askedKey)
    }
}
