//
//  QuoteService+Transcription.swift
//  Verbal
//
//  The live transcript stays on-device and instant. This is a single deferred
//  pass over the saved microphone audio, used immediately before quote
//  extraction when the phone is online.

import Foundation
import Supabase
import Auth

extension QuoteService {
    /// Returns a more accurate transcript, or throws without touching the
    /// on-device transcript. The caller deliberately treats failure as a
    /// fallback: a network service must never make a recording unusable.
    static func refineTranscript(audioURL: URL, rateCard: [RateCardItem]) async throws -> RefinedTranscript {
        let data = try Data(contentsOf: audioURL)
        // The Edge Function has the same ceiling. This equates to roughly
        // twelve minutes of the 16 kHz mono capture; longer recordings retain
        // the live transcript rather than risking a huge foreground upload.
        guard data.count <= 25 * 1_024 * 1_024 else { throw TranscriptionError.audioTooLong }
        guard let accessToken = client.auth.currentSession?.accessToken else {
            throw TranscriptionError.notSignedIn
        }

        let endpoint = SupabaseConfig.url.appending(path: "functions/v1/transcribe-audio")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("audio/x-caf", forHTTPHeaderField: "Content-Type")
        request.setValue(keytermsHeader(for: rateCard), forHTTPHeaderField: "X-Verbal-Keyterms")

        // A deadline, because `URLSession` does not give one that means anything
        // here: its 60 seconds count *inactivity*, so audio trickling up a bad
        // connection never trips it and the user watches a spinner for as long
        // as it takes. This pass is optional by design — the on-device
        // transcript is already complete and correct enough to quote from — so
        // waiting past the point of usefulness buys nothing and costs the one
        // moment the app is judged on.
        //
        // 45 seconds, not the extraction's own budget: the function uploads to
        // the provider and then polls it for up to thirty, so a tighter ceiling
        // here would cut off passes that were about to succeed. Generous enough
        // to let a normal one finish, short enough that a stalled one is over
        // before the user gives up on it.
        // An immutable copy to hand the closure: `request` is a `var` because it
        // is built up field by field above, and capturing one in a @Sendable
        // closure is an error under Swift 6.
        let uploadRequest = request
        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await withTimeout(.seconds(45)) {
                try await URLSession.shared.upload(for: uploadRequest, from: data)
            }
        } catch is TimedOutError {
            throw TranscriptionError.timedOut
        }
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse }
        let body = try? JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
        guard (200..<300).contains(http.statusCode), let text = body?.transcript,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.remote(body?.error ?? "The accuracy pass failed.")
        }
        return RefinedTranscript(text: text, model: body?.model)
    }

    /// The rate-card names the transcriber should listen for, as a header value.
    ///
    /// Two things constrain this, and the old `prefix(1_000)` respected
    /// neither. A header value must be ASCII, so a rate card with "Réparation"
    /// or "£/m²" in it produced a value URLRequest cannot carry; and edge
    /// runtimes cap total header bytes at around 16 KB, so a mature rate card
    /// took the whole request down with a protocol error rather than degrading.
    /// Percent-encoding fixes the first, and a byte budget the second: terms
    /// are added until the value would exceed it, which fails soft — a shorter
    /// prompt still helps the transcriber, while a rejected request helps
    /// nobody.
    private static func keytermsHeader(for rateCard: [RateCardItem]) -> String {
        /// Well inside the ~16 KB ceiling once the other headers are counted.
        let byteBudget = 4_000
        /// AssemblyAI weights a focused prompt more heavily than an exhaustive
        /// one, and the server applies the same cap.
        let maxTerms = 100

        var kept: [String] = []
        for name in rateCard.map(\.name) {
            let term = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Matches the server's own filter, so a term can't be dropped there
            // after being paid for in the budget here.
            guard !term.isEmpty, term.count <= 50 else { continue }
            guard let candidate = encodedTerms(kept + [term]) else { continue }
            guard candidate.utf8.count <= byteBudget else { break }
            kept.append(term)
            if kept.count == maxTerms { break }
        }
        return encodedTerms(kept) ?? "%5B%5D"
    }

    /// JSON, then percent-encoded so every byte is header-safe. The server
    /// decodes before parsing.
    private static func encodedTerms(_ terms: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(terms),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    }
}

struct RefinedTranscript: Sendable {
    let text: String
    /// Supplied by the provider response, so UI never claims an accuracy pass
    /// succeeded unless it has actually completed.
    let model: String?
}

private struct TranscriptionResponse: Decodable {
    let transcript: String?
    let model: String?
    let error: String?
}

enum TranscriptionError: LocalizedError {
    case audioTooLong, notSignedIn, invalidResponse, timedOut, remote(String)
    /// Shown to the user on the review screen, after "Accuracy check wasn't
    /// used:" — so each of these has to read as a reason a person can act on,
    /// not as a thrown type. A timeout in particular must never reach them as
    /// `TimedOutError`'s own description.
    var errorDescription: String? {
        switch self {
        case .audioTooLong: return "This recording is too long for the accuracy pass."
        case .notSignedIn: return "Sign in to use the accuracy pass."
        case .invalidResponse: return "The accuracy pass returned an invalid response."
        case .timedOut: return "It was taking too long on this connection."
        case .remote(let message): return message
        }
    }
}
