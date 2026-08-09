//
//  AvatarView.swift
//  Verbal
//

import SwiftUI

/// Circular avatar. Prefers a preloaded image (fetched during bootstrap so it
/// shows with no visible load); otherwise loads from the URL, falling back to a
/// person icon.
struct AvatarView: View {
    var image: Image?
    var urlString: String?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder
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
