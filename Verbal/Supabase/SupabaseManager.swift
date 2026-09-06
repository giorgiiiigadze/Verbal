//
//  SupabaseManager.swift
//  Verbal
//

import Foundation
import Supabase

/// Single shared Supabase client for the app.
enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                // Keep a foreground session alive before its short-lived access
                // token expires. This is currently the SDK default, but making
                // it explicit prevents a future dependency update from quietly
                // turning routine token expiry into a sign-in prompt.
                autoRefreshToken: true,
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}
