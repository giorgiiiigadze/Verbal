//
//  EmailAuthView.swift
//  Verbal
//
//  The two screens behind "Continue with email": an address, then the code
//  that was mailed to it.
//
//  Presented over the sign-in screen rather than beside it, on the same
//  backdrop, because it is the same act continued — the provider buttons sign
//  you in without leaving that screen, and this shouldn't feel like a different
//  part of the app for having a keyboard in it.
//

import SwiftUI

struct EmailAuthView: View {
    /// Fires the moment the code is accepted, before the account's data is
    /// loaded. The sign-in screen owns the wait from there: it puts its own
    /// finishing screen up and stays until `SessionStore` swaps it out, so
    /// there is no gap between this and the app.
    var onSignedIn: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkMonitor.self) private var network

    private enum Step { case email, code }
    private enum Field: Hashable { case email, code }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var toast: Toast?
    /// Seconds until another code can be asked for. Counted down rather than
    /// hidden, so "send a new one" is never a button that fails.
    @State private var resendIn = 0
    @FocusState private var focused: Field?

    var body: some View {
        ZStack {
            AuthBackground()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                switch step {
                case .email: emailStep
                case .code: codeStep
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Email sign in")
        .navigationBarTitleDisplayMode(.inline)
        // The code screen's back action changes its form state instead of
        // popping the auth route, so it owns that one toolbar item.
        .navigationBarBackButtonHidden(step == .code)
        .toolbar {
            if step == .code {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel(
                        step == .code ? "Change email address" : "Back to sign-in options"
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if step == .email {
                primaryButton(
                    title: "Send code",
                    isBusy: isSending,
                    isEnabled: EmailAuth.isPlausible(email),
                    action: sendCode
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .toast($toast)
        // The keyboard is the point of both screens; nothing here should have
        // to be tapped twice to be typed into. Focus is set a beat late on
        // purpose — asked for while the cover is still travelling, iOS drops it
        // and the field comes up dead.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            focused = .email
        }
    }

    // MARK: - Email

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What's your email?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            Text("We'll send you a six-digit code. No password to remember.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("you@yourbusiness.com", text: $email)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Color(.mainText))
                .tint(Color(.blueAccentText))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused, equals: .email)
                .onSubmit(sendCode)
                .onChange(of: email) { toast = nil }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(Color(.cardSurface))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            focused == .email ? Color(.blueAccentText) : Color(.separator),
                            lineWidth: 1
                        )
                }
                .padding(.top, 6)
        }
    }

    // MARK: - Code

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter your code")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            Text("Sent to \(EmailAuth.normalized(email))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            codeField
                .padding(.top, 6)
            resendControl
        }
    }

    /// Six boxes with one real field behind them. A `TextField` per box has to
    /// hand focus along on every keystroke and fights the delete key at every
    /// boundary; this way the text is one string, and the boxes are only a
    /// drawing of it.
    private var codeField: some View {
        ZStack {
            // The real control, left in the accessibility tree and given the
            // label the boxes are only drawing. Hiding it and exposing the
            // drawing instead would leave VoiceOver with something it can
            // select and nothing it can type into.
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused, equals: .code)
                .tint(.clear)
                .foregroundStyle(.clear)
                // Not `.hidden`, and not zero: a field with no opacity at all
                // cannot take focus, and the keyboard never comes up.
                .opacity(0.01)
                .accessibilityLabel("Six-digit code")
                .accessibilityValue(
                    code.isEmpty ? "Empty" : code.map(String.init).joined(separator: " ")
                )
                .onChange(of: code) { _, newValue in
                    let cleaned = EmailAuth.sanitize(newValue)
                    if cleaned != newValue { code = cleaned }
                    toast = nil
                    if cleaned.count == EmailAuth.codeLength { verify(cleaned) }
                }

            HStack(spacing: 8) {
                ForEach(0..<EmailAuth.codeLength, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = .code }
    }

    private func digitBox(at index: Int) -> some View {
        let digits = Array(code)
        let digit = index < digits.count ? String(digits[index]) : ""
        // The caret sits on the next empty box, or on the last one once the
        // code is full — so a wrong code shows where the correction goes.
        let isActive = focused == .code
            && index == min(digits.count, EmailAuth.codeLength - 1)

        return Text(digit)
            // Fixed, like the initials in an avatar: the box is 58pt tall
            // whatever the type size, and a digit that scales past it is a
            // digit sticking out of its own outline.
            .font(.robotoSlabFixed(24))
            .foregroundStyle(Color(.mainText))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color(.cardSurface))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isActive ? Color(.blueAccentText) : Color(.separator),
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
    }

    private var resendControl: some View {
        HStack(spacing: 6) {
            if isVerifying {
                ProgressView()
                    .controlSize(.small)
                Text("Checking your code…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isSending {
                ProgressView()
                    .controlSize(.small)
                Text("Sending a new code…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if resendIn > 0 {
                Text("You can ask for a new code in \(resendIn)s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("Send a new code") { sendCode(resending: true) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.blueAccentText))
            }
        }
        // A row that appears and disappears would shunt the boxes up and down
        // every time the state changed underneath them.
        .frame(minHeight: 22, alignment: .leading)
        .task(id: resendIn) {
            guard resendIn > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            resendIn -= 1
        }
    }

    // MARK: - Shared pieces

    private func goBack() {
        if step == .code {
            withAnimation { step = .email }
            code = ""
            toast = nil
            focused = .email
        } else {
            dismiss()
        }
    }

    /// The same shell the provider buttons use, so this reads as the third one
    /// of them rather than a form control that arrived from somewhere else.
    private func primaryButton(
        title: String,
        isBusy: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.body.weight(.semibold))
                if isBusy {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.black, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }

    // MARK: - Actions

    private func sendCode() { sendCode(resending: false) }

    private func sendCode(resending: Bool) {
        guard !isSending else { return }
        guard EmailAuth.isPlausible(email) else {
            showError(EmailAuthError.invalidEmail.errorDescription)
            return
        }
        guard network.isOnline else {
            showError("You're offline. Connect and try again.")
            return
        }

        isSending = true
        toast = nil
        Task {
            defer { isSending = false }
            do {
                try await EmailAuth.sendCode(to: email)
                code = ""
                if !resending { withAnimation { step = .code } }
                resendIn = EmailAuth.resendInterval
                // Same beat as on appear: the code field does not exist yet in
                // the frame the step changes in.
                try? await Task.sleep(for: .milliseconds(250))
                focused = .code
            } catch {
                guard !error.isCancellation else { return }
                showError(error.localizedDescription)
            }
        }
    }

    private func verify(_ code: String) {
        guard !isVerifying else { return }
        focused = nil
        isVerifying = true
        toast = nil
        Task {
            do {
                try await EmailAuth.verify(email: email, code: code)
                // Deliberately still `isVerifying`: the sign-in screen's
                // finishing overlay comes up behind this before it dismisses,
                // and re-enabling the field for that instant would flash a
                // live keyboard target under a loading screen.
                onSignedIn()
            } catch {
                isVerifying = false
                guard !error.isCancellation else { return }
                showError(error.localizedDescription)
                focused = .code
            }
        }
    }

    private func showError(_ message: String?) {
        toast = Toast(style: .error, message: message ?? "Something went wrong. Try again.")
    }
}

#Preview("Email auth") {
    EmailAuthView(onSignedIn: {})
        .environment(NetworkMonitor())
}
