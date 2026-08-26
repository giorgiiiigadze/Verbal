//
//  AppInfo.swift
//  Verbal
//
//  Version, support and legal links surfaced in Settings.
//

import Foundation
import UIKit

enum AppInfo {
    /// e.g. "1.0 (3)" — shown in Settings and included in support emails so a
    /// report can be tied to an exact build.
    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    static let supportEmail = "gio.giorgigiorgadze20@gmail.com"

    /// Served by GitHub Pages from `docs/privacy` on main. The path is
    /// case-sensitive and has to match the repository name exactly — the
    /// lowercase spelling this used to carry returned a 404.
    static let privacyPolicyURL = URL(string: "https://giorgiiiigadze.github.io/Verbal/privacy/")!

    /// Same host and the same case-sensitivity trap as the privacy policy.
    /// Optional in type only now — the row it feeds has to be reachable from
    /// the paywall once subscriptions ship, and App Review checks.
    static let termsURL: URL? = URL(string: "https://giorgiiiigadze.github.io/Verbal/terms/")

    /// Where a shared quote is read. The page is hosted here rather than on the
    /// Supabase function that feeds it because that gateway stamps every
    /// response with `content-security-policy: default-src 'none'; sandbox` and
    /// rewrites the content type to text/plain — sensible on a shared domain,
    /// but it leaves HTML unstyled and its buttons dead.
    static func shareURL(token: String) -> URL? {
        URL(string: "https://giorgiiiigadze.github.io/Verbal/q/#\(token)")
    }

    /// Nil until the app is on the App Store and has a numeric id. Until then
    /// there is nothing to review and no page to open.
    static let appStoreID: String? = nil

    /// Opens the App Store straight onto the review sheet. Preferred over
    /// `requestReview` for a row the user deliberately tapped: Apple throttles
    /// that prompt and will silently show nothing, and a control that sometimes
    /// does nothing teaches people the app is unreliable.
    static var reviewURL: URL? {
        guard let appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    /// A support email pre-filled with the details that would otherwise be the
    /// first three replies of every conversation.
    static var supportMailURL: URL? {
        let device = UIDevice.current
        let body = """


        —
        Verbal \(versionLabel)
        \(device.systemName) \(device.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Verbal support"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
