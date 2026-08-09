//
//  LineItemsSheet.swift
//  Verbal
//
//  Editing the priced lines of a quote: add, remove, reorder-by-deletion, and
//  a pushed editor per item.
//
//  This used to be one section inside "Edit quote", below the title, summary
//  and scope. Those are three text fields; this is where the money is, and it
//  was reached by opening a form about something else and scrolling past it.
//  It now opens from the line-items card itself, so the thing being edited is
//  the thing that was tapped.
//

import SwiftUI
import UIKit

struct LineItemsSheet: View {
    let quoteId: UUID
    let currency: String
    /// Needed only to show the total the way the quote screen shows it. The
    /// database derives tax and total from the subtotal this sheet writes.
    let taxRate: Double
    /// Reports the new figures so the screen behind can update without waiting
    /// for a refetch.
    var onSaved: (_ subtotal: Double, _ total: Double) -> Void

    @Environment(\.dismiss) private var dismiss
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
         lineItems: [QuoteLineItem],
         onSaved: @escaping (Double, Double) -> Void) {
        self.quoteId = quoteId
        self.currency = currency
        self.taxRate = taxRate
        self.onSaved = onSaved
        // Built with an explicit loop (not `.map`) so the value-type initializer
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
    /// the one to show here and hand back to the quote screen.
    private var total: Double {
        let tax = (subtotal * taxRate / 100).roundedToCents
        return (subtotal + tax).roundedToCents
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } footer: {
                    Text("Swipe a line to remove it.")
                }
                .listRowBackground(Color(.cardSurface))

                Section {
                    HStack {
                        Text("Total").font(.headline)
                        Spacer()
                        Text(total, format: AppCurrency.format(code: currency))
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

            // Only the subtotal: a database trigger derives tax and total from
            // it, so writing those here would be this screen's arithmetic
            // overruling the server's on the way past.
            try await QuoteService.updateSubtotal(id: quoteId, subtotal: newSubtotal)
        } catch {
            // Staying open on a failed write is the point: closing with a
            // success haptic would tell the user their prices were saved when
            // they weren't, and they'd find out days later.
            saveError = true
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSaved(newSubtotal, newTotal)
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
