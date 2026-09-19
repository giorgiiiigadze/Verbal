//
//  AppearanceView.swift
//  Verbal
//
//  A native settings sheet. The selection is applied immediately, while the
//  sheet itself uses the standard iOS navigation and list affordances.
//

import SwiftUI

struct AppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.defaultsKey) private var selected = AppAppearance.system.rawValue

    private var current: AppAppearance {
        AppAppearance(rawValue: selected) ?? .system
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AppAppearance.allCases) { appearance in
                        appearanceRow(appearance)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System matches your iPhone. Light and Dark keep Verbal in the appearance you choose until you change it again.")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func appearanceRow(_ appearance: AppAppearance) -> some View {
        Button {
            guard current != appearance else { return }
            selected = appearance.rawValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appearance.label)
                    Text(appearance.sheetSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if current == appearance {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .foregroundStyle(Color(.mainText))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(current == appearance
            ? "Current appearance"
            : "Sets Verbal to \(appearance.label.lowercased()) appearance")
    }
}

#Preview {
    AppearanceSheet()
}
