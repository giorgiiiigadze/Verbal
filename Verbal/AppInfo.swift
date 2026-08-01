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

    // IMPORTANT: both pages must be live before submitting to the App Store —
    // a privacy policy URL is required, and the terms link is required once
    // subscriptions ship. Replace these with the real addresses.
    static let privacyPolicyURL = URL(string: "https://giorgiiiigadze.github.io/verbal/privacy")!
    static let termsURL = URL(string: "https://giorgiiiigadze.github.io/verbal/terms")!

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
