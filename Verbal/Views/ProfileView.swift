//
//  ProfileView.swift
//  Verbal
//

import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AvatarView(urlString: session.profile?.avatarUrl, size: 88)
                    if let fullName = session.profile?.fullName, !fullName.isEmpty {
                        Text(fullName).font(.title3.bold())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            if let bio = session.profile?.bio, !bio.isEmpty {
                Section("Bio") {
                    Text(bio)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
