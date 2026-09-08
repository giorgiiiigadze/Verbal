//
//  GeneratedQuoteEditorSheet.swift
//  Verbal
//
//  Editing the line items of a freshly generated quote, before it is finalized.
//
//  Deliberately the same sheet as the one on a saved quote (`LineItemsSheet`):
//  a Form of tappable summary rows, a pushed editor per line, add and
//  swipe-to-remove, and a live total. The only difference is where the edits
//  go — this one hands a `GeneratedQuote` back to the recording screen instead
//  of writing rows, because the draft is banked separately.
//

import SwiftUI

struct GeneratedQuoteEditorSheet: View {
    let quote: GeneratedQuote
    let currency: String
    let onSave: (GeneratedQuote) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [EditableGeneratedItem]
    /// The list as it opened, so Save can stay disabled until something has
    /// actually changed — the same rule the saved-quote sheet uses.
    private let originalItems: [EditableGeneratedItem]

    init(quote: GeneratedQuote, currency: String, onSave: @escaping (GeneratedQuote) -> Void) {
        self.quote = quote
        self.currency = currency
        self.onSave = onSave
        // An explicit loop rather than `.map`, so the value-type initializer
        // isn't called from a nonisolated map closure under main-actor isolation.
        var built: [EditableGeneratedItem] = []
        for item in quote.lineItems { built.append(EditableGeneratedItem(item)) }
        _items = State(initialValue: built)
        originalItems = built
    }

    private var hasChanges: Bool { items != originalItems }

    /// Live subtotal from the currently-entered quantities and prices. No tax
    /// here: an unsaved quote has no rate yet, and the review screen behind
    /// this one shows the same untaxed figure.
    private var subtotal: Double {
        items.reduce(0) { $0 + ($1.lineTotal ?? 0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($items) { $item in
                        NavigationLink {
                            GeneratedLineItemEditor(item: $item, currency: currency)
                        } label: {
                            GeneratedLineItemSummaryRow(item: item, currency: currency)
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }

                    Button {
                        items.append(EditableGeneratedItem())
                    } label: {
                        Label("Add item", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Line items")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.mainText))
                        .textCase(nil)
                } footer: {
                    Text("Swipe a line to remove it.")
                }
                .listRowBackground(Color(.cardSurface))

                Section {
                    HStack {
                        Text("Total").font(.headline)
                        Spacer()
                        Text(subtotal, format: AppCurrency.format(code: currency))
                            .font(.headline.monospacedDigit())
                    }
                }
                .listRowBackground(Color(.cardSurface))
            }
            .scrollContentBackground(.hidden)
            .background(Color(.homeBackground))
            .navigationTitle("Line items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var edited = quote
                        var lines: [GeneratedLineItem] = []
                        for item in items { lines.append(item.generated) }
                        edited.lineItems = lines
                        onSave(edited)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
        }
    }
}

// MARK: - Line-item summary row

/// Compact, tappable row: name on the left, price (or "Needs price") on the right.
private struct GeneratedLineItemSummaryRow: View {
    let item: EditableGeneratedItem
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
        .padding(.vertical, 8)
    }
}

// MARK: - Line-item editor (pushed screen)

/// A full, labeled editor for one generated line item.
private struct GeneratedLineItemEditor: View {
    @Binding var item: EditableGeneratedItem
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
            .listRowBackground(Color(.cardSurface))

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
            .listRowBackground(Color(.cardSurface))

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
            .listRowBackground(Color(.cardSurface))
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

/// A generated line item in an editable, text-field-friendly form.
private struct EditableGeneratedItem: Identifiable, Equatable {
    /// Compared on the fields the user can change. `id` is view-local identity,
    /// minted fresh each time the sheet is built, so a synthesised `==` would
    /// report every line as changed and defeat the point.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.description == rhs.description
            && lhs.type == rhs.type
            && lhs.quantityText == rhs.quantityText
            && lhs.unit == rhs.unit
            && lhs.priceText == rhs.priceText
    }

    let id = UUID()
    var description: String
    var type: String
    var quantityText: String
    var unit: String
    var priceText: String
    /// Carried through untouched so an edit elsewhere on the line doesn't erase
    /// what the model said about this one.
    var confidence: String?

    /// New, blank item added via "Add item".
    init() {
        description = ""
        type = "other"
        quantityText = "1"
        unit = ""
        priceText = ""
        confidence = nil
    }

    init(_ item: GeneratedLineItem) {
        description = item.description
        type = item.type
        quantityText = item.quantity.map { $0.formattedQuantity } ?? ""
        unit = item.unit ?? ""
        priceText = item.unitPrice.map { $0.formattedQuantity } ?? ""
        confidence = item.confidence
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

    /// Back to the model the review screen draws from.
    ///
    /// A hand-typed price is recorded as "spoken", the same as the saved-quote
    /// sheet does: `price_source` is constrained to spoken / rate_card /
    /// missing, so the truthful-looking "manual" is rejected by the database,
    /// and nothing reads the column except the "missing" test.
    var generated: GeneratedLineItem {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return GeneratedLineItem(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            quantity: quantity,
            unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
            unitPrice: unitPrice,
            priceSource: unitPrice == nil ? "missing" : "spoken",
            confidence: confidence
        )
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
