//
//  OnboardingDraft.swift
//  Verbal
//
//  Onboarding runs before there is an account, so what it collects has to wait
//  on the device until one exists. The trade already worked this way; this holds
//  the rest of the answers on the same terms.
//
//  Written once and then cleared, so a user who later empties one of these
//  fields doesn't find it restored on the next launch.
//

import Foundation

struct OnboardingDraft: Codable, Sendable {
    struct Rate: Codable, Sendable {
        let name: String
        let unit: String
        let price: Double
        let type: String
    }

    var businessName: String?
    /// Percentage, e.g. 20 for 20% VAT. Nil when the question was skipped —
    /// which is not the same as zero, and only zero should write a zero.
    var taxRate: Double?
    var rates: [Rate] = []

    var isEmpty: Bool {
        (businessName ?? "").isEmpty && taxRate == nil && rates.isEmpty
    }

    // MARK: - Storage

    private static let key = "onboardingDraft"

    static func load() -> OnboardingDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
