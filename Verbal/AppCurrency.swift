//
//  AppCurrency.swift
//  Verbal
//
//  The user's main currency, used to format quote and rate-card amounts.
//

import Foundation

enum AppCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case jpy = "JPY"
    case inr = "INR"
    case aed = "AED"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .usd, .cad, .aud: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .chf: return "CHF"
        case .jpy: return "¥"
        case .inr: return "₹"
        case .aed: return "د.إ"
        }
    }

    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .cad: return "Canadian Dollar"
        case .aud: return "Australian Dollar"
        case .chf: return "Swiss Franc"
        case .jpy: return "Japanese Yen"
        case .inr: return "Indian Rupee"
        case .aed: return "UAE Dirham"
        }
    }

    /// The label shown in the picker, e.g. "British Pound (£)".
    var label: String { "\(displayName) (\(symbol))" }

    /// Default derived from the device locale, falling back to USD.
    static var deviceDefault: AppCurrency {
        if let code = Locale.current.currency?.identifier,
           let match = AppCurrency(rawValue: code) {
            return match
        }
        return .usd
    }
}
