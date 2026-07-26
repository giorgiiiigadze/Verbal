//
//  HomeView.swift
//  Verbal
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Home")
                        .font(.title.bold())
                    if let name = session.profile?.fullName, !name.isEmpty {
                        Text("Welcome back, \(name).")
                            .foregroundStyle(.secondary)
                    }
                    Text("Your feed will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        AvatarView(urlString: session.profile?.avatarUrl, size: 30)
                    }
                }
            }
        }
    }
}
