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

    /// The user's currently selected currency, read from the persisted setting.
    static var current: AppCurrency {
        let code = UserDefaults.standard.string(forKey: "mainCurrency")
        return code.flatMap(AppCurrency.init(rawValue:)) ?? deviceDefault
    }

    /// A `FormatStyle` for the current currency, for use in `Text(_, format:)`.
    static var currentFormat: FloatingPointFormatStyle<Double>.Currency {
        .currency(code: current.rawValue)
    }

    /// Format an amount as a string in the current currency, e.g. "£1,250.00".
    static func format(_ amount: Double) -> String {
        amount.formatted(currentFormat)
    }

    /// A `FormatStyle` for a specific ISO code (a quote's own currency),
    /// falling back to the current setting when the code is missing.
    static func format(code: String?) -> FloatingPointFormatStyle<Double>.Currency {
        .currency(code: code ?? current.rawValue)
    }

    /// Format an amount as a string in a specific currency, falling back to
    /// the current setting when the code is missing.
    static func format(_ amount: Double, code: String?) -> String {
        amount.formatted(format(code: code))
    }
}
