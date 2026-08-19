//
//  QuoteService.swift
//  Verbal
//
//  Everything the app asks of Supabase about quotes.
//
//  The surface is wide — quotes, their lines, customers, the rate card, the
//  transcript, and the one Edge Function that turns speech into a quote — so it
//  is split by subject across `QuoteService+*.swift` rather than kept as one
//  flat list of forty calls. The domain types it reads and writes live in
//  Models/; each file here holds only the private payloads its own calls encode.
//

import Foundation
import Supabase

enum QuoteService {
    /// Internal rather than private: the calls live in extensions in other
    /// files, and `private` would put the connection out of their reach.
    static var client: SupabaseClient { SupabaseManager.client }
}
