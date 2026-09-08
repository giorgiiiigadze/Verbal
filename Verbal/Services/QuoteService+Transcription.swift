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
        let terms = rateCard.prefix(1_000).map(\.name)
        request.setValue(try String(data: JSONEncoder().encode(terms), encoding: .utf8),
                         forHTTPHeaderField: "X-Verbal-Keyterms")

        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse }
        let body = try? JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
        guard (200..<300).contains(http.statusCode), let text = body?.transcript,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.remote(body?.error ?? "The accuracy pass failed.")
        }
        return RefinedTranscript(text: text, model: body?.model)
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
    case audioTooLong, notSignedIn, invalidResponse, remote(String)
    var errorDescription: String? {
        switch self {
        case .audioTooLong: return "This recording is too long for the accuracy pass."
        case .notSignedIn: return "Sign in to use the accuracy pass."
        case .invalidResponse: return "The accuracy pass returned an invalid response."
        case .remote(let message): return message
        }
    }
}
