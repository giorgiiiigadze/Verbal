//
//  CreateView.swift
//  Verbal
//

import SwiftUI

struct CreateView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Create")
                    .font(.title.bold())
                Text("Compose something new here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Create")
        }
    }
}
