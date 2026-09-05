//
//  OnboardingQuoteDraft.swift
//  Verbal
//
//  Turning what someone just said into priced lines, on the phone, with no
//  account and no network.
//
//  The real extraction is an Edge Function behind a signed-in user: it reads
//  quantities, materials, the customer's name, and it is far better at this
//  than the fifty lines below. It is also unreachable during onboarding, and
//  the alternative — a canned card claiming to be their quote — was the thing
//  this screen exists to stop being.
//
//  So this is the honest half of the trick: their real voice, transcribed on
//  device, matched against the rates they typed four screens ago. Everything
//  on the card is theirs. The screen says plainly that the full extraction
//  does more, because it does.
//

import Foundation

struct OnboardingQuoteDraft {
    struct Line: Identifiable {
        let id = UUID()
        let description: String
        let quantity: Int
        let unit: String
        /// Nil where nothing on the rate card matched — the same "Needs price"
        /// state the real quote screen shows, and for the same reason.
        let price: Double?
    }

    let lines: [Line]

    var total: Double {
        lines.reduce(0) { $0 + Double($1.quantity) * ($1.price ?? 0) }
    }

    var isEmpty: Bool { lines.isEmpty }

    /// Words that appear in half the rate names there are, and so can't tell
    /// two of them apart. Matching on "a" and "the" matched everything.
    private static let ignored: Set<String> = [
        "and", "the", "for", "with", "per", "into", "from", "out",
        "new", "old", "job", "each", "day", "rate", "fee", "one"
    ]

    private static let spokenNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "a": 1, "an": 1, "couple": 2, "pair": 2
    ]

    static func build(transcript: String, rates: [OnboardingDraft.Rate]) -> OnboardingQuoteDraft {
        let words = tokens(in: transcript)
        guard !words.isEmpty else { return OnboardingQuoteDraft(lines: []) }

        var lines: [Line] = []
        for rate in rates {
            let keywords = tokens(in: rate.name).filter {
                $0.count > 3 && !ignored.contains($0)
            }
            guard !keywords.isEmpty else { continue }
            let hits = keywords.filter { keyword in
                words.contains { $0 == keyword || stem($0) == stem(keyword) }
            }
            // Half the distinctive words, and never fewer than two unless the
            // name only had one to give. One word in common is a coincidence —
            // "fit" matches a fitted wardrobe and a fitted tap alike.
            let needed = max(1, (keywords.count + 1) / 2)
            guard hits.count >= needed else { continue }
            guard let anchor = words.firstIndex(where: { word in
                hits.contains { $0 == word || stem($0) == stem(word) }
            }) else { continue }
            lines.append(Line(description: rate.name,
                              quantity: quantity(before: anchor, in: words),
                              unit: rate.unit,
                              price: rate.price))
        }

        // Nothing on the card matched, but they did say something. Showing it
        // back unpriced is truthful and still demonstrates the half of the app
        // that flags what nobody priced — which is the half a new user most
        // needs to see, because their card is nearly empty.
        if lines.isEmpty {
            lines.append(Line(description: firstClause(of: transcript),
                              quantity: 1,
                              unit: "job",
                              price: nil))
        }
        return OnboardingQuoteDraft(lines: lines)
    }

    // MARK: - Reading the words

    private static func tokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// A plural and its singular are the same word for this purpose. Crude on
    /// purpose: a real stemmer is a dependency, and the whole job here is to
    /// stop "sockets" missing "socket".
    private static func stem(_ word: String) -> String {
        guard word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    /// The number said just before the thing it counts — "three mixer taps".
    /// Looks back a few words rather than one, because "three of the mixer
    /// taps" is the same sentence. Anything unfound is one, which is what
    /// people mean when they don't say a number at all.
    private static func quantity(before anchor: Int, in words: [String]) -> Int {
        let start = max(0, anchor - 3)
        guard start < anchor else { return 1 }
        for index in stride(from: anchor - 1, through: start, by: -1) {
            let word = words[index]
            if let digits = Int(word), digits > 0, digits < 1000 { return digits }
            if let spoken = spokenNumbers[word] { return spoken }
        }
        return 1
    }

    /// The opening of what they said, trimmed to something that fits on a row.
    /// Cut at a word boundary — a description ending mid-word reads as a bug,
    /// not as an excerpt.
    private static func firstClause(of transcript: String) -> String {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSentence = clean.split(whereSeparator: { ".,;".contains($0) })
            .first.map(String.init) ?? clean
        let trimmed = firstSentence.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 58 else { return trimmed }
        let cut = trimmed.prefix(58)
        let atWord = cut.lastIndex(of: " ").map { String(cut[cut.startIndex..<$0]) } ?? String(cut)
        return atWord + "…"
    }
}
