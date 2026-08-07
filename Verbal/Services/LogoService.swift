//
//  LogoService.swift
//  Verbal
//
//  The business logo: the one piece of the user's own identity on a document a
//  customer keeps. Stored in the `business-logos` bucket under a folder named
//  after the owner, and referenced from `business_profiles.logo_url`.
//

import Foundation
import UIKit
import Supabase

enum LogoService {
    private static var client: SupabaseClient { SupabaseManager.client }
    private static let bucket = "business-logos"

    /// Long edge, in pixels. A logo prints about 40pt tall on an A4 page, so
    /// 512 is already generous at any sane print density — and it keeps a photo
    /// taken of a van door from becoming a four-megabyte upload over cellular.
    private static let maxDimension: CGFloat = 512

    /// Upload a new logo and return its public URL.
    ///
    /// Written under a fresh filename every time rather than replacing one at a
    /// fixed path: a public bucket is served through a CDN, and reusing the URL
    /// means a user who changes their logo keeps seeing — and printing — the old
    /// one until some cache somewhere expires.
    static func upload(_ image: UIImage) async throws -> String {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        guard let data = pngData(from: image) else {
            throw LogoError.unreadableImage
        }
        let path = "\(userID.uuidString)/\(UUID().uuidString).png"
        try await client.storage
            .from(bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/png"))
        return try client.storage.from(bucket).getPublicURL(path: path).absoluteString
    }

    /// Best effort. A logo left behind costs a few kilobytes; a failure here
    /// must never be the reason a user's new logo doesn't get saved.
    static func removeStored(at urlString: String?) async {
        guard let path = storagePath(from: urlString) else { return }
        _ = try? await client.storage.from(bucket).remove(paths: [path])
    }

    /// Turn a public URL back into the object path the storage API expects.
    /// Nil for anything that isn't one of ours — an empty field, or a URL from
    /// some earlier scheme — so those are left alone rather than guessed at.
    private static func storagePath(from urlString: String?) -> String? {
        guard let urlString, let range = urlString.range(of: "/\(bucket)/") else { return nil }
        let path = String(urlString[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    /// PNG, and downscaled only when it's actually too big.
    ///
    /// PNG rather than JPEG because logos are the one image class that really
    /// needs transparency: a mark with a white box baked around it sits on the
    /// quote like a sticker, and the quote is the thing the user is trying to
    /// look professional on.
    private static func pngData(from image: UIImage) -> Data? {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else { return image.pngData() }

        let scale = maxDimension / longEdge
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format)
            .pngData { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}

enum LogoError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "That image couldn't be read."
        }
    }
}
