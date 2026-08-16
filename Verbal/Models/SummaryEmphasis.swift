//
//  SummaryEmphasis.swift
//  Verbal
//
//  Sets the load-bearing facts in a job summary heavier than the prose around
//  them, so a deposit or a validity period is found by looking rather than by
//  reading.
//
//  Derived at display time rather than stored. The summary is one string, and
//  the PDF, the search, the edit sheet, the share text and Home's row all read
//  the same one — mark it up at the source and every one of them has to learn
//  to strip the markup back out. Doing it here means none of them change, and
//  quotes written before any of this existed get it too.
//

import SwiftUI

/// The job summary with its facts — money, shares, spans of time, dates — set
/// heavier than the prose, or all one weight when emphasis wouldn't help.
///
/// A point larger than the scope bullets beneath it, and otherwise identical:
/// same medium prose, same bold facts. The summary is the sentence that says
/// what the job is and scope is the checklist under it, so it leads — but on
/// size alone. Setting the bullets a weight lighter was tried and made them
/// read as a different kind of text rather than as a quieter one.
///
/// Both weights are set here, and the call site must NOT add `.fontWeight()`
/// of its own: that modifier is applied over every run in the string, so a
/// `.fontWeight(.medium)` outside flattens the bold set inside and the whole
/// thing renders in one weight. It looks like the matching failed. It hasn't.
func emphasizedSummary(_ text: String, font: Font = .callout) -> AttributedString {
    var attributed = AttributedString(text)
    attributed.font = font.weight(.medium)
    guard let ranges = emphasisRanges(in: text) else { return attributed }

    for range in ranges {
        guard let bounds = Range(range, in: attributed) else { continue }
        // Bold, because the ground it stands on is already medium. Semibold
        // against medium is one step, and at this size that step is invisible.
        attributed[bounds].font = font.weight(.bold)
    }
    return attributed
}

/// A scope bullet with its count set heavier — "Day-of coordination with
/// **two assistants**", "Centerpieces on **twelve tables**".
///
/// A narrower rule than the summary's, because a bullet is a different kind of
/// sentence. It carries no money, no dates and no terms — the prompt keeps
/// those out of scope on purpose — so the only fact in one is how many of
/// something the customer is getting, and that is the number they count back
/// against the line items. One per bullet: a phrase of six words with two bold
/// fragments in it is just a bold phrase.
///
func emphasizedScopeItem(_ text: String, font: Font = .subheadline) -> AttributedString {
    var attributed = AttributedString(text)
    // Medium and bold, the same pair the summary wears. The bullets were tried
    // a step lighter, on the reasoning that five of them under a paragraph
    // would out-shout it — but at one weight down they read as a different
    // kind of text rather than as a quieter one. The summary stays dominant on
    // size instead, which is the axis that can carry it without the two
    // looking unrelated.
    attributed.font = font.weight(.medium)
    guard let range = countRange(in: text),
          let bounds = Range(range, in: attributed) else { return attributed }
    attributed[bounds].font = font.weight(.bold)
    return attributed
}

/// The first count-and-noun in a bullet, if it has one.
///
/// One match rather than the summary's four. The bullets carry the same
/// weights it does, so the restraint has to come from how many of them are
/// emphasised rather than from how hard.
private func countRange(in text: String) -> NSRange? {
    let full = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = scopeCountRegex?.firstMatch(in: text, range: full) else { return nil }
    // Never the whole bullet. "Two assistants" as a complete item would be set
    // entirely in bold, which says nothing about which part matters.
    guard match.range.length < text.utf16.count else { return nil }
    return match.range
}

/// The ranges worth emphasising, or nil when the answer is "none of them".
///
/// Nil rather than an empty array on purpose: the interesting outcomes are
/// "here are two facts" and "don't touch this paragraph", and the second is a
/// decision rather than the absence of one.
private func emphasisRanges(in text: String) -> [NSRange]? {
    // A short summary is already one glance. Emphasis inside it just makes two
    // weights out of a sentence that was legible as one.
    guard text.count >= 40 else { return nil }

    let full = NSRange(text.startIndex..<text.endIndex, in: text)
    var found: [NSRange] = []
    for regex in emphasisRegexes {
        found += regex.matches(in: text, range: full).map(\.range)
    }
    guard !found.isEmpty else { return nil }

    let merged = merging(found.sorted { $0.location < $1.location })

    // The whole point is that a few things stand out. Past four, nothing does
    // — a paragraph in six weights reads as noise, and it is exactly the
    // number-dense summary where the patterns below are most likely to be
    // catching something that isn't a term at all. Leave it alone instead.
    //
    // Four rather than three because a summary that states a date, a headcount,
    // a deposit and a validity period has four facts in it, and dropping the
    // whole paragraph to plain for having one too many is the wrong way to
    // fail. The share of the text is the real guard.
    guard merged.count <= 4 else { return nil }
    let emphasised = merged.reduce(0) { $0 + $1.length }
    guard Double(emphasised) / Double(text.utf16.count) <= 0.3 else { return nil }

    return merged
}

/// Overlapping and touching matches joined into one run.
///
/// The single-character gap matters as much as the overlap: "30% deposit" is
/// two patterns meeting across a space, and left apart it would bold two
/// fragments of one phrase and spend two of the four slots below on it.
private func merging(_ ranges: [NSRange]) -> [NSRange] {
    var merged: [NSRange] = []
    for range in ranges {
        if let last = merged.last, NSIntersectionRange(last, range).length > 0
            || range.location - last.upperBound <= 1 {
            merged[merged.count - 1] = NSUnionRange(last, range)
        } else {
            merged.append(range)
        }
    }
    return merged
}

/// Every currency symbol the app can show, escaped for use in a pattern. Built
/// from `AppCurrency` rather than written as `[£$€]` — CHF and د.إ are symbols
/// too, and a hard-coded three would quietly fail for anyone using them.
private let currencyPattern: String = {
    let symbols = Set(AppCurrency.allCases.map(\.symbol))
        .map { NSRegularExpression.escapedPattern(for: $0) }
        .sorted { $0.count > $1.count }
    return symbols.joined(separator: "|")
}()

/// Compiled once. These are called from view bodies — a summary and up to six
/// bullets, re-evaluated on every scroll and every animation frame — and
/// rebuilding twelve regular expressions each pass is real work on the main
/// thread to arrive at the same objects every time.
private let emphasisRegexes: [NSRegularExpression] = emphasisPatterns.compactMap {
    try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
}

private let scopeCountRegex = try? NSRegularExpression(pattern: scopeCountPattern,
                                                       options: [.caseInsensitive])

/// A count and the thing being counted, for scope bullets.
///
/// The noun is taken as whatever word follows rather than matched against a
/// list of units: scope is written in the customer's language and counts
/// anything the job happens to involve — assistants, tables, coats, sockets —
/// and a list would always be missing the one this job needed. The summary's
/// own count pattern does use a list, because there a bare number beside a
/// word is as likely to be a house number as a quantity.
private let scopeCountPattern =
    #"\b(?:\d[\d,]*|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+"#
    + #"[A-Za-z][A-Za-z-]+\b"#

/// What counts as a fact in a quote summary.
///
/// Deliberately narrow. These are the things a tradesperson looks back at a
/// quote to check — what was agreed, how much of it up front, and how long it
/// stands. Adjectives and job descriptions are not on the list: the summary is
/// already about the job, so emphasising "bathroom re-tiling" in a paragraph
/// about a bathroom re-tiling says nothing.
private let emphasisPatterns: [String] = [
    // Money: a symbol against a number, with optional thousands and decimals.
    #"(?:\#(currencyPattern))\s?\d[\d,]*(?:\.\d+)?"#,
    // A share, written either way round.
    #"\d+(?:\.\d+)?\s?%"#,
    #"\b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|half)\s+per\s?cent\b"#,
    // A span of time, in digits or words.
    #"\b(?:\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|twelve)\s+"#
    + #"(?:hour|day|week|month|year|working\s+day)s?\b"#,
    // Dates, spelled or numeric.
    #"\b\d{1,2}(?:st|nd|rd|th)?\s+"#
    + #"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\b"#,
    #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?\b"#,
    #"\b(?:next|this)\s+(?:Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day\b"#,
    // A time of day, which in a summary is always an access arrangement.
    #"\b\d{1,2}(?::\d{2})?\s?(?:am|pm)\b"#,
    // A count against a unit — "150 guests", "20 m²", "3 bedrooms". The unit
    // is required: a bare number is as likely to be a house number as a
    // quantity, and "14 Prospect Row" is not a fact about the job.
    #"\b\d[\d,]*(?:\.\d+)?\s?"#
    + #"(?:m²|m2|sq\s?m|sqft|ft²|m\b|km\b|kg\b|litres?\b|liters?\b|"#
    + #"guests?|people|persons?|rooms?|bedrooms?|bathrooms?|windows?|doors?|"#
    + #"coats?|panels?|units?|sockets?|radiators?)"#,
    // The two words that change what the money means. Not facts with numbers
    // in them, but the term a number belongs to — "deposit" is the difference
    // between a payment and a price, and it is what the user looks back for.
    //
    // Only these two, deliberately. "up front", "on completion", "balance due"
    // and the rest were tried and pushed summaries past the cap below, so a
    // paragraph stating a deposit, an amount and a date — the case emphasis
    // exists for — went entirely plain. A longer list of weaker words costs
    // the strong ones their slot.
    #"\bnon-?refundable\b"#,
    #"\bdeposits?\b"#,
]
