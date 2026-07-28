//
//  FXService.swift
//  Verbal
//
//  Fetches daily exchange rates for optional currency conversion of a quote.
//  Uses Frankfurter (frankfurter.app) — free, no API key, ECB reference rates
//  updated once per business day. Not every currency is supported (the ECB
//  list is ~30 majors), so callers must handle `unsupported`.
//

import Foundation

enum FXService {
    private struct RateResponse: Decodable {
        let rates: [String: Double]
    }

    enum FXError: LocalizedError {
        case unsupported
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Automatic conversion isn't available for this currency pair."
            case .badResponse:
                return "Couldn't fetch today's exchange rate. Check your connection and try again."
            }
        }
    }

    /// Today's rate to multiply a `from` amount by to get `to`. Returns 1 when
    /// the currencies match. Throws `unsupported` / `badResponse` on failure.
    static func rate(from: String, to: String) async throws -> Double {
        if from == to { return 1 }

        var components = URLComponents(string: "https://api.frankfurter.app/latest")!
        components.queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ]
        guard let url = components.url else { throw FXError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw FXError.badResponse }
        // Frankfurter returns 404 for currencies it doesn't cover (e.g. AED).
        if http.statusCode == 404 { throw FXError.unsupported }
        guard http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(RateResponse.self, from: data),
              let rate = decoded.rates[to] else {
            throw FXError.badResponse
        }
        return rate
    }
}
