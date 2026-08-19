//
//  FXService.swift
//  Verbal
//
//  Fetches daily exchange rates for optional currency conversion of a quote.
//  Uses Frankfurter (frankfurter.app) — free, no API key, ECB reference rates
//  updated once per business day. Not every currency is supported (the ECB
//  list is ~30 majors), so callers must handle `unsupported`.
//
//  Rates are cached per base currency for the current day (in memory and in
//  UserDefaults), so only the first conversion of the day hits the network —
//  subsequent ones resolve instantly with no spinner.
//

import Foundation

enum FXService {
    private struct RateResponse: Decodable {
        let rates: [String: Double]
    }

    /// One base currency's full rate table, tagged with the day it was fetched.
    private struct CachedTable: Codable {
        let day: String
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

    private static var memoryCache: [String: CachedTable] = [:]

    /// Today as a plain yyyy-MM-dd key in UTC (matches how ECB rates roll over).
    private static var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Today's rate to multiply a `from` amount by to get `to`. Returns 1 when
    /// the currencies match. Uses a per-day cache; only the first lookup for a
    /// given base currency each day makes a network request.
    static func rate(from: String, to: String) async throws -> Double {
        if from == to { return 1 }
        let table = try await ratesTable(base: from)
        guard let rate = table[to] else { throw FXError.unsupported }
        return rate
    }

    /// What today's cache can say about a pair without going near the network.
    ///
    /// Three answers, not an optional, because "we can never price this" and
    /// "we haven't fetched yet" are opposite instructions to the caller: the
    /// first means carry on without the quote, the second means wait.
    enum CachedRate {
        /// Today's table for this base has the pair.
        case known(Double)
        /// Today's table is here and has no such pair — the ECB list is ~30
        /// majors, so this is a permanent no, not a slow yes.
        case unsupported
        /// No table for this base yet today. Only `rate(from:to:)` can answer.
        case needsFetch
    }

    /// Today's rate from the cache alone. Never makes a request, so it is safe
    /// to call while a view is being drawn — which is the point of it: a figure
    /// that can be totalled during `body` needs no spinner over it.
    static func cachedRate(from: String, to: String) -> CachedRate {
        if from == to { return .known(1) }
        guard let table = cachedTable(base: from) else { return .needsFetch }
        guard let rate = table[to] else { return .unsupported }
        return .known(rate)
    }

    /// Warm the cache for a base currency in the background (best effort), so
    /// the first real conversion resolves instantly. Errors are ignored.
    static func prefetch(base: String) async {
        _ = try? await ratesTable(base: base)
    }

    /// The full rate table for a base currency, from cache when fresh.
    private static func ratesTable(base: String) async throws -> [String: Double] {
        if let cached = cachedTable(base: base) { return cached }

        guard var components = URLComponents(string: "https://api.frankfurter.app/latest") else {
            throw FXError.badResponse
        }
        components.queryItems = [URLQueryItem(name: "from", value: base)]
        guard let url = components.url else { throw FXError.badResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw FXError.badResponse }
        // Frankfurter returns 404 for currencies it doesn't cover (e.g. AED).
        if http.statusCode == 404 { throw FXError.unsupported }
        guard http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(RateResponse.self, from: data) else {
            throw FXError.badResponse
        }
        store(base: base, rates: decoded.rates)
        return decoded.rates
    }

    // MARK: - Cache

    private static func cacheKey(_ base: String) -> String { "fxRates_\(base)" }

    private static func cachedTable(base: String) -> [String: Double]? {
        if let mem = memoryCache[base], mem.day == today { return mem.rates }
        if let data = UserDefaults.standard.data(forKey: cacheKey(base)),
           let decoded = try? JSONDecoder().decode(CachedTable.self, from: data),
           decoded.day == today {
            memoryCache[base] = decoded
            return decoded.rates
        }
        return nil
    }

    private static func store(base: String, rates: [String: Double]) {
        let table = CachedTable(day: today, rates: rates)
        memoryCache[base] = table
        if let data = try? JSONEncoder().encode(table) {
            UserDefaults.standard.set(data, forKey: cacheKey(base))
        }
    }
}
