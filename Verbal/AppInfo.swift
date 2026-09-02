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

    /// Verbal's public home on the web.
    static let websiteURL = URL(string: "https://www.theverbal.app")!

    /// The privacy policy shown from onboarding, paywall, and About.
    static let privacyPolicyURL = URL(string: "https://www.theverbal.app/privacy")!

    /// The terms shown from onboarding, paywall, and About.
    static let termsURL: URL? = URL(string: "https://www.theverbal.app/terms")

    /// Where a shared quote is read. The page is hosted on the marketing site
    /// rather than on the Supabase function that feeds it because that gateway
    /// stamps every response with `content-security-policy: default-src 'none';
    /// sandbox` and rewrites the content type to text/plain — sensible on a
    /// shared domain, but it leaves HTML unstyled and its buttons dead.
    ///
    /// The origin here must match an entry in the quote function's
    /// `ALLOWED_ORIGINS`, or the page's fetch is refused by CORS. `www` is the
    /// canonical host — the apex redirects to it — so this points straight at
    /// `www` rather than taking a redirect hop that would drop the trailing
    /// slash and could drop the token in the fragment with it.
    static func shareURL(token: String) -> URL? {
        URL(string: "https://www.theverbal.app/q/#\(token)")
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
