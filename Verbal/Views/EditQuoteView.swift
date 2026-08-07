//
//  EditQuoteView.swift
//  Verbal
//
//  Edit a saved quote: title, job summary, and line items (description,
//  quantity, unit, unit price — including pricing "Needs price" items).
//  Totals are always recomputed in code, never trusted from the old value.
//

import SwiftUI

struct EditQuoteView: View {
    let quoteId: UUID
    /// The quote's currency code, for formatting prices and the total.
    let currency: String
    /// The quote's tax percentage. The database derives the total from the
    /// subtotal and this rate, so the screen has to apply it too or it would
    /// show a different number than the one being stored.
    let taxRate: Double
    /// Called after a successful save with the new title, job summary, scope, and
    /// total so the detail screen can reflect the edits without a full refetch.
    var onSaved: (_ title: String, _ jobSummary: String, _ scope: [String], _ total: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Carried through untouched. Renaming lives in the detail screen's menu,
    /// behind a native alert; this screen still has to write the title back,
    /// because saving rewrites the whole row and a title left out is a title
    /// erased.
    private let title: String
    @State private var jobSummary: String
    /// Scope edited as one bullet per line; blank lines are dropped on save.
    @State private var scopeText: String
    @State private var items: [EditableLineItem]
    /// Server ids present when editing began, to compute deletions on save.
    private let originalIDs: Set<UUID>
    @State private var isSaving = false
    /// Set when a write failed, so the sheet reports it instead of closing on
    /// edits that were never stored.
    @State private var saveError = false

    init(quoteId: UUID,
         currency: String,
         taxRate: Double,
         title: String,
         jobSummary: String,
         scope: [String],
         lineItems: [QuoteLineItem],
         onSaved: @escaping (String, String, [String], Double) -> Void) {
        self.quoteId = quoteId
        self.currency = currency
        self.taxRate = taxRate
        self.onSaved = onSaved
        self.title = title
        _jobSummary = State(initialValue: jobSummary)
        _scopeText = State(initialValue: scope.joined(separator: "\n"))
        // Build with an explicit loop (not `.map`) so the value-type initializer
        // isn't called from a nonisolated map closure under main-actor isolation.
        var built: [EditableLineItem] = []
        for item in lineItems { built.append(EditableLineItem(item)) }
        _items = State(initialValue: built)
        originalIDs = Set(lineItems.map(\.id))
    }

    /// Live subtotal from the currently-entered quantities and prices.
    private var subtotal: Double {
        items.reduce(0) { $0 + ($1.lineTotal ?? 0) }
    }

    /// Subtotal plus tax — the figure the database will hold once saved, and so
    /// the one to show here and hand back to the detail screen.
    private var total: Double {
        let tax = (subtotal * taxRate / 100).roundedToCents
        return (subtotal + tax).roundedToCents
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Job summary", text: $jobSummary, axis: .vertical)
                        .lineLimit(2...5)
                }
                .listRowBackground(Color(.surface))

                Section {
                    TextField("One item per line", text: $scopeText, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Scope of work")
                } footer: {
                    Text("Each line becomes a bullet on the quote.")
                }
                .listRowBackground(Color(.surface))

                Section("Line items") {
                    ForEach($items) { $item in
                        NavigationLink {
                            LineItemEditorView(item: $item, currency: currency)
                        } label: {
                            LineItemSummaryRow(item: item, currency: currency)
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }

                    Button {
                        items.append(EditableLineItem())
                    } label: {
                        Label("Add item", systemImage: "plus.circle.fill")
                    }
                }
                .listRowBackground(Color(.surface))

                Section {
                    HStack {
                        Text("Total").font(.headline)
                        Spacer()
                        Text(total, format: AppCurrency.format(code: currency))
                            .font(.headline.monospacedDigit())
                    }
                }
                .listRowBackground(Color(.surface))
            }
            .scrollContentBackground(.hidden)
            .background(Color(.homeBackground))
            .navigationTitle("Edit quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert("Couldn't save your changes", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and tap Save again. Your edits are still here.")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSummary = jobSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let newScope = scopeText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let newSubtotal = subtotal
        let newTotal = total

        do {
            // Delete items removed during editing.
            let survivingIDs = Set(items.compactMap(\.serverID))
            for removed in originalIDs.subtracting(survivingIDs) {
                try await QuoteService.deleteLineItem(id: removed)
            }

            // Update existing items and insert new ones, preserving order.
            for (index, item) in items.enumerated() {
                let source = item.unitPrice != nil ? "spoken" : "missing"
                let description = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                if let serverID = item.serverID {
                    try await QuoteService.updateLineItem(
                        id: serverID,
                        description: description.isEmpty ? nil : description,
                        type: item.type,
                        quantity: item.quantity,
                        unit: unit.isEmpty ? nil : unit,
                        unitPrice: item.unitPrice,
                        priceSource: source,
                        position: index
                    )
                } else {
                    try await QuoteService.insertLineItem(
                        quoteId: quoteId,
                        description: description.isEmpty ? nil : description,
                        type: item.type,
                        quantity: item.quantity,
                        unit: unit.isEmpty ? nil : unit,
                        unitPrice: item.unitPrice,
                        priceSource: source,
                        position: index
                    )
                }
            }

            try await QuoteService.updateQuoteCore(
                id: quoteId,
                title: newTitle.isEmpty ? nil : newTitle,
                jobSummary: newSummary.isEmpty ? nil : newSummary,
                scope: newScope,
                subtotal: newSubtotal,
                total: newTotal
            )
        } catch {
            // Staying open on a failed write is the point: closing with a
            // success haptic would tell the user their prices were saved when
            // they weren't, and they'd find out days later.
            saveError = true
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSaved(newTitle, newSummary, newScope, newTotal)
        dismiss()
    }
}

// MARK: - Line-item summary row

/// Compact, tappable row: name on the left, price (or "Needs price") on the right.
private struct LineItemSummaryRow: View {
    let item: EditableLineItem
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.description.isEmpty ? "New item" : item.description)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(item.description.isEmpty ? .secondary : Color(.mainText))
                    .lineLimit(1)
                if let subtitle = item.quantitySubtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let lineTotal = item.lineTotal {
                Text(lineTotal, format: AppCurrency.format(code: currency))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
            } else {
                HStack(spacing: 6) {
                    Circle().fill(LineItemRow.amber).frame(width: 7, height: 7)
                    Text("Needs price")
                        .font(.footnote)
                        .foregroundStyle(LineItemRow.amber)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Line-item editor (pushed screen)

/// A full, labeled editor for one line item.
private struct LineItemEditorView: View {
    @Binding var item: EditableLineItem
    let currency: String
    @Environment(\.dismiss) private var dismiss

    private let commonUnits = ["each", "m²", "m", "hour", "day", "job", "litre", "kg"]
    private let types = ["labor", "material", "other"]

    /// Unit options always include the item's current unit so the picker can show it.
    private var unitOptions: [String] {
        var options = commonUnits
        if !item.unit.isEmpty && !options.contains(item.unit) {
            options.insert(item.unit, at: 0)
        }
        return options
    }

    private var currencySymbol: String {
        AppCurrency(rawValue: currency)?.symbol ?? currency
    }

    var body: some View {
        Form {
            Section("Description") {
                TextField("e.g. Re-tiling bathroom floor", text: $item.description, axis: .vertical)
                    .lineLimit(1...3)
            }
            .listRowBackground(Color(.surface))

            Section("Pricing") {
                LabeledContent("Quantity") {
                    TextField("1", text: $item.quantityText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Unit", selection: $item.unit) {
                    Text("None").tag("")
                    ForEach(unitOptions, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Unit price") {
                    HStack(spacing: 4) {
                        Text(currencySymbol).foregroundStyle(.secondary)
                        TextField("0.00", text: $item.priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Picker("Type", selection: $item.type) {
                    ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            .listRowBackground(Color(.surface))

            Section {
                LabeledContent("Line total") {
                    if let lineTotal = item.lineTotal {
                        Text(lineTotal, format: AppCurrency.format(code: currency))
                            .font(.headline.monospacedDigit())
                    } else {
                        Text("Needs price").foregroundStyle(LineItemRow.amber)
                    }
                }
            }
            .listRowBackground(Color(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Editable model

/// A line item in an editable, text-field-friendly form.
private struct EditableLineItem: Identifiable {
    let id = UUID()
    /// The database id, nil for a newly-added item.
    var serverID: UUID?
    var description: String
    var type: String
    var quantityText: String
    var unit: String
    var priceText: String

    /// New, blank item added via "Add item".
    init() {
        serverID = nil
        description = ""
        type = "other"
        quantityText = "1"
        unit = ""
        priceText = ""
    }

    init(_ item: QuoteLineItem) {
        serverID = item.id
        description = item.description ?? ""
        type = item.type
        quantityText = item.quantity.map { $0.formattedQuantity } ?? ""
        unit = item.unit ?? ""
        priceText = item.unitPrice.map { $0.formattedQuantity } ?? ""
    }

    var quantity: Double? { Double(quantityText.replacingOccurrences(of: ",", with: ".")) }
    var unitPrice: Double? {
        let cleaned = priceText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
    var lineTotal: Double? {
        guard let quantity, let unitPrice else { return nil }
        return quantity * unitPrice
    }

    /// e.g. "18 m²" or "1 each" — nil when there's nothing to show.
    var quantitySubtitle: String? {
        let qty = quantity.map { $0.formattedQuantity } ?? quantityText
        let parts = [qty, unit].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

private extension Double {
    /// Whole numbers render without decimals; others keep up to two.
    var formattedQuantity: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(self))
            : String(format: "%.2f", self)
    }
}
