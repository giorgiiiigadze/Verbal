//
//  OnboardingView.swift
//  Verbal
//
//  Three screens between installing the app and signing in.
//
//  Deliberately not a carousel of promises. The first screen shows the app
//  doing its one trick, because a voice-to-quote app is easier to prove than to
//  describe; the other two ask the only questions worth asking before there is
//  an account — and both of their answers do real work rather than being
//  collected for their own sake.
//
//  They run before auth, so there is no user to save anything to. Both answers
//  are held on the device and written to the profile on the first sign-in.
//

import SwiftUI

struct OnboardingView: View {
    /// Called when the last step is finished, to hand over to the auth screen.
    var onContinue: () -> Void

    @AppStorage("pendingTrade") private var pendingTrade = ""
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    @State private var step = 0
    @Namespace private var glass

    /// Jobs ticked on the presets step, and the prices typed for them. Held as
    /// text so a half-typed number doesn't fight the field.
    @State private var pickedJobs: Set<String> = []
    @State private var prices: [String: String] = [:]
    @State private var businessName = ""
    @State private var taxRate = ""
    @State private var isTaxRegistered = false
    /// The reveal holds its sample back for a beat. Not theatre for its own
    /// sake: the answers just given are being turned into something, and a card
    /// that snaps in fully formed reads as one that was always there.
    @State private var revealed = false

    private enum Step: Hashable {
        case showcase, trade, jobs, prices, business, reveal
    }

    /// The steps this particular user will see. A trade with no preset list
    /// skips the jobs question rather than being shown a list that fits nobody,
    /// and pricing is skipped when nothing was ticked to price.
    private var steps: [Step] {
        var list: [Step] = [.showcase, .trade]
        if !TradePresets.jobs(for: pendingTrade).isEmpty {
            list.append(.jobs)
            if !pickedJobs.isEmpty { list.append(.prices) }
        }
        list.append(contentsOf: [.business, .reveal])
        return list
    }

    /// Clamped, because `steps` shrinks underneath the index when someone swipes
    /// back and unticks every job.
    private var current: Step {
        let all = steps
        return all[min(step, all.count - 1)]
    }

    private var pickedList: [TradePresets.Job] {
        TradePresets.jobs(for: pendingTrade).filter { pickedJobs.contains($0.name) }
    }

    /// What the user typed, as rates worth saving. A blank or unparseable price
    /// is left out rather than saved as a rate with no price — the rate card
    /// exists to avoid exactly that.
    private var draftRates: [OnboardingDraft.Rate] {
        pickedList.compactMap { job in
            let text = (prices[job.name] ?? "").replacingOccurrences(of: ",", with: ".")
            guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value > 0
            else { return nil }
            return OnboardingDraft.Rate(name: job.name, unit: job.unit,
                                        price: value, type: TradePresets.type)
        }
    }

    private static let trades = [
        "Electrician", "Plumber", "Carpenter", "Tiler",
        "Painter", "Plasterer", "Builder", "Roofer",
        "Landscaper", "Something else"
    ]

    var body: some View {
        ZStack {
            // The same drawn ground as the sign-in screen, so these three and
            // the one they hand over to read as a single entrance rather than
            // as two apps meeting in the middle.
            AuthBackground()

            VStack(alignment: .leading, spacing: 0) {
                header

                Group {
                    switch current {
                    case .showcase: showcase
                    case .trade: tradeStep
                    case .jobs: jobsStep
                    case .prices: pricesStep
                    case .business: businessStep
                    case .reveal: revealStep
                    }
                }
                // Each step arrives from the side it was going, so the sequence
                // reads as forward motion rather than as three unrelated
                // screens sharing a background.
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity.combined(with: .offset(x: -24))
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            // Less than the sides: the home indicator already reserves space
            // below this, and matching 24 to it left the button floating well
            // clear of the bottom of the screen.
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        // The only way back, so it is worth being generous about what counts as
        // one: a shallow drag rightwards, the same direction the steps travel,
        // rather than a precise edge swipe nobody would find.
        //
        // Vertical movement is ignored, so a thumb sliding down the chips
        // doesn't jump a step.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { drag in
                    guard step > 0 else { return }
                    let sideways = drag.translation.width
                    let vertical = abs(drag.translation.height)
                    if sideways > 60, sideways > vertical * 1.5 { step -= 1 }
                }
        )
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Image(.brandMark)
                .resizable()
                .scaledToFit()
                .frame(width: 24)
                .foregroundStyle(Color(.blueAccentText))
            Text("Verbal")
                .font(.robotoSlab(22, relativeTo: .title3))
                .foregroundStyle(Color(.blueAccentText))
            Spacer()
            // Six steps need an end in sight more than three did.
            HStack(spacing: 5) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index == step
                              ? Color(.blueAccentText)
                              : Color(.blueAccentText).opacity(0.22))
                        .frame(width: index == step ? 16 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: step)
        }
        .padding(.bottom, 28)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                advance()
            } label: {
                Text(current == .reveal ? "Get started" : "Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.royalBlue600), in: Capsule())
            }
            .buttonStyle(.plain)

            // Skip alone, centred. Going back is the swipe — see the gesture on
            // the body. Two text buttons flanking the primary one made the
            // footer read as a toolbar, and this screen has one thing to do.
            //
            // The row keeps its height on the first step, where Skip doesn't
            // apply, so the button above doesn't shift as the steps change.
            // Color.clear rather than an empty branch: a `Group` with nothing
            // in it collapses to an EmptyView, which reserves no height no
            // matter what frame is put on it — so the button was sitting 36pt
            // lower on the first step and jumping up on the second.
            ZStack {
                Color.clear
                // Never a wall. Both questions have sensible answers already,
                // and nobody should be stuck on the way to the thing they
                // installed the app for.
                // Not on the reveal: nothing is being asked there, so a Skip
                // beside "Get started" offers to skip past the payoff.
                if step > 0, current != .reveal {
                    Button("Skip") { advance() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 22)
        }
    }

    private func advance() {
        guard current != .reveal else {
            saveDraft()
            onContinue()
            return
        }
        step += 1
    }

    /// Everything but the trade, which already has its own key and its own
    /// adoption. Saved on the way out rather than as it's typed: half an answer
    /// isn't worth carrying into an account.
    private func saveDraft() {
        var draft = OnboardingDraft()
        let name = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.businessName = name.isEmpty ? nil : name
        if isTaxRegistered {
            let typed = Double(taxRate.replacingOccurrences(of: ",", with: "."))
            draft.taxRate = typed.map { max(0, $0) }
        }
        draft.rates = draftRates
        if draft.isEmpty { OnboardingDraft.clear() } else { draft.save() }
    }

    // MARK: - Step 1 · what it does

    /// Shown, not described. The transformation is the product, and a sentence
    /// claiming it happens is weaker than eight lines demonstrating it.
    private var showcase: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Say the job.\nGet the quote.")
                .font(.robotoSlab(34, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Text("“Remove the old toilet and fit the new one, ninety. Three mixer taps. Eight metres of the 20 mil pipe.”")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.blueAccentText).opacity(0.5))
                    .frame(maxWidth: .infinity)

                LineItemsCard {
                    LineItemRow(description: "Remove old toilet and fit new toilet",
                                quantityText: "1 each", isMissingPrice: false,
                                lineTotal: 90, currencyCode: currencyCode)
                    Divider()
                    LineItemRow(description: "Mixer taps", quantityText: "3 each",
                                isMissingPrice: true, lineTotal: nil,
                                currencyCode: currencyCode)
                    Divider()
                    LineItemRow(description: "20 mil pipe", quantityText: "8 m",
                                isMissingPrice: true, lineTotal: nil,
                                currencyCode: currencyCode)
                }
            }

            Text("Prices you didn't say are flagged, never guessed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2 · trade

    private var tradeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's your trade?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))

            Text("So a quote knows that “20 mil” means your 20 mil.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // A grid of taps rather than a text field: this is answered once,
            // standing in a van, and a keyboard is the slowest way to say a
            // word the app could have offered.
            FlowLayout(spacing: 8) {
                ForEach(Self.trades, id: \.self) { trade in
                    Button {
                        pendingTrade = pendingTrade == trade ? "" : trade
                    } label: {
                        Text(trade)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(pendingTrade == trade
                                             ? .white : Color(.mainText))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(pendingTrade == trade
                                        ? Color(.royalBlue600) : Color(.cardSurface),
                                        in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    pendingTrade == trade ? .clear : Color(.separator),
                                    lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: pendingTrade)
        }
    }

    // MARK: - Step 3 · the jobs they do

    /// Ticking, not typing. The point of this screen is that it can be answered
    /// while holding something in the other hand.
    private var jobsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Which of these\ndo you do?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            Text("Verbal prices these for you automatically when you quote them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                ForEach(TradePresets.jobs(for: pendingTrade)) { job in
                    let picked = pickedJobs.contains(job.name)
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        if picked { pickedJobs.remove(job.name) } else { pickedJobs.insert(job.name) }
                    } label: {
                        Text(job.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(picked ? .white : Color(.mainText))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(picked ? Color(.royalBlue600) : Color(.cardSurface),
                                        in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(picked ? .clear : Color(.separator),
                                                       lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: pickedJobs)
        }
    }

    // MARK: - Step 4 · what they charge

    /// Currency lives here rather than on a screen of its own: it is the same
    /// question as "what do you charge", asked in the same breath, and it is
    /// already answered from the device's region for most people.
    private var pricesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Roughly what\ndo you charge?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            Text("A rough number beats none — you can correct any of them later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AppCurrency.allCases) { option in
                        Button {
                            currencyCode = option.rawValue
                        } label: {
                            Text("\(option.symbol) \(option.rawValue)")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(currencyCode == option.rawValue
                                                 ? .white : Color(.mainText))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(currencyCode == option.rawValue
                                            ? Color(.royalBlue600) : Color(.cardSurface),
                                            in: Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        currencyCode == option.rawValue
                                            ? .clear : Color(.separator),
                                        lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(pickedList) { job in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(job.name)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Color(.mainText))
                                    .lineLimit(1)
                                Text("per \(job.unit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 3) {
                                Text(AppCurrency.current.symbol)
                                    .foregroundStyle(.secondary)
                                TextField("0", text: Binding(
                                    get: { prices[job.name] ?? "" },
                                    set: { prices[job.name] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                            }
                            .font(.callout.monospacedDigit())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color(.cardSurface),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Step 5 · the business

    private var businessStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's your\nbusiness called?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            // Asked here because the alternative is asking at the worst possible
            // moment: today the first attempt to share a quote stops to collect
            // this, with a customer waiting on the other end.
            Text("It goes at the top of every quote you send.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("e.g. Kapanadze Plumbing", text: $businessName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.cardSurface),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )

            Toggle(isOn: $isTaxRegistered.animation(.easeInOut(duration: 0.2))) {
                Text("I'm tax registered")
                    .font(.callout)
                    .foregroundStyle(Color(.mainText))
            }
            .tint(Color(.royalBlue600))

            if isTaxRegistered {
                HStack(spacing: 8) {
                    Text("Rate")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("20", text: $taxRate)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.callout.monospacedDigit())
                        .frame(width: 60)
                    Text("%").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.cardSurface),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Step 6 · the reveal

    /// Their own answers, priced, before they have signed up for anything.
    ///
    /// Canned on purpose: a live recording here would need the microphone before
    /// the app has earned it, and a poor first extraction is a poor first
    /// impression. Everything on this card is real — their trade, their
    /// currency, the prices they just typed — it simply isn't spoken.
    private var revealStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(revealed ? "Your first quote is\nhalf-written already." : "Setting up\nyour rate card…")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.3), value: revealed)

            if revealed {
                VStack(alignment: .leading, spacing: 12) {
                    Text(sampleSpokenLine)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(.blueAccentText).opacity(0.5))
                        .frame(maxWidth: .infinity)

                    LineItemsCard {
                        ForEach(Array(sampleLines.enumerated()), id: \.offset) { index, line in
                            if index > 0 { Divider() }
                            LineItemRow(description: line.name,
                                        quantityText: "1 \(line.unit)",
                                        isMissingPrice: line.price == nil,
                                        lineTotal: line.price,
                                        currencyCode: currencyCode)
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 12)))

                Text(draftRates.isEmpty
                     ? "Prices you haven't set are flagged, never guessed."
                     : "Saved to your rate card. Speak a job and these fill themselves in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView()
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .task {
            guard !revealed else { return }
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.35)) { revealed = true }
        }
    }

    /// Two of their own rates and one they didn't price, so the sample shows
    /// both halves of what the app does — filling prices in, and flagging the
    /// ones nobody said.
    private var sampleLines: [(name: String, unit: String, price: Double?)] {
        var lines = draftRates.prefix(2).map {
            (name: $0.name, unit: $0.unit, price: Optional($0.price))
        }
        if lines.isEmpty {
            lines = [(name: "First job on the list", unit: "each", price: nil)]
        }
        lines.append((name: "Materials from the supplier", unit: "job", price: nil))
        return lines
    }

    private var sampleSpokenLine: String {
        let named = draftRates.first?.name.lowercased() ?? "the job"
        return "“\(named), and the materials from the supplier — I'll price those tomorrow.”"
    }
}

/// Wraps its children onto as many rows as they need.
///
/// A `LazyVGrid` with fixed columns would give every trade the width of
/// "Something else", leaving "Tiler" adrift in a mostly empty cell. These read
/// as words, so they should be sized like words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total = CGSize(width: 0, height: 0)

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
