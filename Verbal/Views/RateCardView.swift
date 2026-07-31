//
//  RateCardView.swift
//  Verbal
//
//  The user's saved prices (labor / material / other). These feed the AI
//  extraction so known items get priced automatically instead of flagged.
//

import SwiftUI

struct RateCardView: View {
    @Environment(SessionStore.self) private var session
    @State private var items: [RateCardItem] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var showAdd = false
    @State private var itemToDelete: RateCardItem?
    @State private var toast: Toast?

    var body: some View {
        Group {
            if items.isEmpty && !hasLoaded {
                // Still loading first paint — stay blank, not "no prices".
                Color(.homeBackground)
            } else if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(.homeBackground))
        .navigationTitle("Rate card")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddRateItemView()
        }
        .task {
            // Seed from the splash-time preload so the list shows instantly.
            if !hasLoaded {
                items = session.rateCard
                hasLoaded = session.listsLoaded
            }
            await load()
        }
        .refreshable { await load() }
        .alert("Delete this rate?", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        ), presenting: itemToDelete) { item in
            Button("Delete", role: .destructive) {
                Task { await delete(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("This removes “\(item.name)” from your rate card. This can't be undone.")
        }
        .toast($toast)
    }

    private var list: some View {
        List {
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(Color(.mainText))
                        Text(item.type.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let price = item.priceText {
                        Text(price)
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(Color(.blueAccentText))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.royalBlue25), in: Capsule())
                    } else {
                        Text("No price")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                .contextMenu {
                    Button(role: .destructive) {
                        itemToDelete = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // No .destructive role: it would animate the row out on tap,
                    // before the confirmation alert is answered.
                    Button {
                        itemToDelete = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(Color(.blueAccentText))
                .padding(16)
                .background(Color(.royalBlue25), in: Circle())
                .padding(.bottom, 4)
            Text("No saved prices yet")
                .font(.headline)
                .foregroundStyle(Color(.mainText))
            Text("Add your common labor and material rates so quotes get priced automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items = (try? await QuoteService.fetchRateCard()) ?? []
        hasLoaded = true
    }

    private func delete(_ item: RateCardItem) async {
        do {
            try await QuoteService.deleteRateCardItem(id: item.id)
            items.removeAll { $0.id == item.id }
            toast = Toast(style: .success, message: "Rate deleted")
        } catch {
            toast = Toast(style: .error, message: "Couldn't delete rate")
        }
    }
}

// MARK: - Add form

private struct AddRateItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "each"
    @State private var customUnit = ""
    @State private var priceText = ""
    @State private var type = "labor"
    @State private var isSaving = false

    private let types = ["labor", "material", "other"]
    private let commonUnits = ["each", "m²", "m", "hour", "day", "job", "litre", "kg"]
    private let customTag = "__custom__"

    /// The unit to persist — the picked common unit, or the typed custom one.
    private var resolvedUnit: String? {
        let value = unit == customTag ? customUnit.trimmingCharacters(in: .whitespaces) : unit
        return value.isEmpty ? nil : value
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name (e.g. Re-tiling)", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                .listRowBackground(Color(.surface))

                Section("Price") {
                    TextField("Unit price", text: $priceText)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $unit) {
                        ForEach(commonUnits, id: \.self) { Text($0).tag($0) }
                        Text("Custom…").tag(customTag)
                    }
                    if unit == customTag {
                        TextField("Custom unit", text: $customUnit)
                    }
                }
                .listRowBackground(Color(.surface))
            }
            .scrollContentBackground(.hidden)
            .background(Color(.homeBackground))
            .navigationTitle("New rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let price = Double(priceText.replacingOccurrences(of: ",", with: "."))
        Task {
            try? await QuoteService.addRateCardItem(
                name: name.trimmingCharacters(in: .whitespaces),
                unit: resolvedUnit,
                unitPrice: price,
                type: type
            )
            isSaving = false
            dismiss()
        }
    }
}
