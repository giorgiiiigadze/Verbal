//
//  AvatarView.swift
//  Verbal
//

import SwiftUI

/// Circular avatar that loads a remote image (e.g. the Google profile photo),
/// falling back to a person icon while loading or when no URL is available.
struct AvatarView: View {
    let urlString: String?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.5))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color(.systemGray5), in: Circle())
    }
}
