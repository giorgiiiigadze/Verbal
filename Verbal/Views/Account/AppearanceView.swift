//
//  AppearanceView.swift
//  Verbal
//
//  Lets the user choose whether Verbal follows the device or uses a fixed theme.
//

import SwiftUI

struct AppearanceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearance.defaultsKey) private var selected = AppAppearance.system.rawValue

    private var selectedIconColor: Color {
        colorScheme == .dark ? .white : Color(.royalBlue600)
    }

    private var current: AppAppearance {
        AppAppearance(rawValue: selected) ?? .system
    }

    var body: some View {
        List {
            Section {
                ForEach(AppAppearance.allCases) { appearance in
                    Button {
                        selected = appearance.rawValue
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: appearance.icon)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color(.royalBlue600))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appearance.label)
                                    .foregroundStyle(Color(.mainText))
                                Text(appearance.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if current == appearance {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(selectedIconColor)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("System follows your iPhone's appearance. Light and Dark keep Verbal fixed until you change it again.")
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.accountBackground))
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
