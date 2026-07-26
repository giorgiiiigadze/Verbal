//
//  HomeView.swift
//  Verbal
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var showCreate = false

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
                    Text("Your quotes appear here..")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        // TODO: second action (define what this button does)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        AvatarView(image: session.avatarImage, urlString: session.profile?.avatarUrl, size: 30)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                QuoteRecordingView()
            }
        }
    }
}
