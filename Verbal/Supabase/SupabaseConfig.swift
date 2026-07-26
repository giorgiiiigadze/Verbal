//
//  SupabaseConfig.swift
//  Verbal
//

import Foundation

enum SupabaseConfig {
    static let url = URL(string: "https://rglpwlmkwukezvexyups.supabase.co")!
    // Publishable (anon) key — safe to ship in the client.
    static let anonKey = "sb_publishable_4KHIco2kXA9ldB8aeqyFpw_X191_28e"
}

enum GoogleConfig {
    // iOS OAuth client ID from Google Cloud Console (…apps.googleusercontent.com).
    static let iosClientID = "730414346653-7mm7bs8q82qonlbhupugckcq0h4ngl57.apps.googleusercontent.com"
}
