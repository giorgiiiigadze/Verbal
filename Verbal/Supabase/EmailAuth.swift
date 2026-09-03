//
//  EmailAuth.swift
//  Verbal
//
//  Signing in with an email address and a six-digit code.
//
//  A code rather than a magic link on purpose. A link has to come back into the
//  app through a URL scheme, and it only works on the device that opened the
//  mail — a plumber who reads email on the laptop in the van taps the link and
//  signs the laptop in, not the phone in his hand. A code travels between
//  devices the way a phone number does: you read it and you type it.
//
//  There is no password anywhere in here, and no sign-up path separate from the
//  sign-in one. The same two screens create an account and return to one, which
//  is why the button says "continue" rather than either.
//

import Foundation
import Supabase

enum EmailAuthError: LocalizedError {
    case invalidEmail
    case incorrectCode
    case tooManyRequests
    case signupsClosed
    case noSession

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "That doesn't look like an email address."
        case .incorrectCode:
            // The server cannot tell us which of the two it was, and neither
            // should we: "wrong code" to someone whose code merely aged out
            // sends them hunting for a typo that isn't there.
            return "That code is wrong or has expired. Check the latest email, or send a new one."
        case .tooManyRequests:
            return "Too many attempts. Wait a minute and try again."
        case .signupsClosed:
            return "New accounts aren't being created right now."
        case .noSession:
            return "Signed in, but no session came back. Try again."
        }
    }
}

enum EmailAuth {
    /// The number of digits the code has. GoTrue issues six.
    static let codeLength = 6

    /// How long before the code can be asked for again. GoTrue refuses a second
    /// send to the same address inside its own window (60s by default), so a
    /// shorter countdown here would only offer a button that fails.
    static let resendInterval = 60

    /// Deliberately loose. This exists to catch the missing `@` before a
    /// round trip, not to adjudicate RFC 5322 — the only opinion that counts
    /// is whether the mail arrives, and a regex that rejects a valid address
    /// locks someone out of their own account.
    static func isPlausible(_ email: String) -> Bool {
        let trimmed = normalized(email)
        guard let at = trimmed.firstIndex(of: "@"), trimmed.lastIndex(of: "@") == at else {
            return false
        }
        let local = trimmed[trimmed.startIndex..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        return !local.isEmpty
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
            && !trimmed.contains(" ")
    }

    /// What we send and what we verify against have to be the same string —
    /// GoTrue looks the token up by address, and " Gio@Mail.com " on the second
    /// screen is not the address the first one mailed.
    static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Keeps only what can be a code, and no more of it than fits. The field is
    /// a number pad, but a pasted code arrives with whatever was around it.
    static func sanitize(_ code: String) -> String {
        String(code.filter(\.isNumber).prefix(codeLength))
    }

    /// Emails a fresh code, creating the account if this address has never
    /// signed in before.
    static func sendCode(to email: String) async throws {
        let address = normalized(email)
        guard isPlausible(address) else { throw EmailAuthError.invalidEmail }
        do {
            try await SupabaseManager.client.auth.signInWithOTP(
                email: address,
                // The same screen has to work for a tradesperson opening the
                // app for the first time and for one coming back to a phone
                // they wiped. Refusing to create the account here would make
                // the first of those a dead end with no way out of it.
                shouldCreateUser: true
            )
        } catch {
            throw mapped(error)
        }
    }

    /// Exchanges the code for a session. Supabase's auth listener does the
    /// rest — `SessionStore` is already watching for the `signedIn` event that
    /// this produces, exactly as it does for Google.
    static func verify(email: String, code: String) async throws {
        let address = normalized(email)
        let token = sanitize(code)

        do {
            try await exchange(address: address, token: token, type: .email)
        } catch let error as AuthError where isTokenRejection(error) {
            // A brand-new account's code is minted by the signup mailer, and a
            // returning account's by the magic-link one. `email` is the generic
            // type and covers both on a current GoTrue, but a project whose
            // templates or server version disagree would otherwise fail for
            // every new user — the majority of the people this screen exists
            // for. One extra round trip is cheaper than that.
            do {
                try await exchange(address: address, token: token, type: .signup)
            } catch let retryError as AuthError where isTokenRejection(retryError) {
                // Both types refused it. The code really is wrong or stale.
                throw EmailAuthError.incorrectCode
            } catch {
                throw mapped(error)
            }
        } catch {
            throw mapped(error)
        }
    }

    private static func exchange(address: String, token: String, type: EmailOTPType) async throws {
        let response = try await SupabaseManager.client.auth.verifyOTP(
            email: address,
            token: token,
            type: type
        )
        // `.user` means the server accepted the code but withheld a session —
        // an email-confirmation setting that this flow cannot satisfy. Better
        // to say so than to leave the sign-in screen sitting there.
        guard case .session = response else { throw EmailAuthError.noSession }
    }

    /// True when the server's answer was "that token is no good" rather than
    /// anything about the request itself. GoTrue reports a wrong code and an
    /// expired one identically, so this is also the shape a typo takes.
    private static func isTokenRejection(_ error: AuthError) -> Bool {
        switch error.errorCode {
        case .otpExpired, .validationFailed, .unknown:
            return true
        default:
            return error.message.localizedCaseInsensitiveContains("token")
        }
    }

    private static func mapped(_ error: Error) -> Error {
        guard let authError = error as? AuthError else { return error }
        switch authError.errorCode {
        case .otpExpired:
            return EmailAuthError.incorrectCode
        case .overEmailSendRateLimit, .overRequestRateLimit:
            return EmailAuthError.tooManyRequests
        case .validationFailed:
            return EmailAuthError.invalidEmail
        case .signupDisabled:
            return EmailAuthError.signupsClosed
        default:
            return authError
        }
    }
}
