//
//  SupabaseErrorKinds.swift
//  Verbal
//
//  Telling one server refusal from another.
//
//  A companion to `ErrorCancellation`, and there for the same reason: a caller
//  that can only see "it threw" has to treat a deliberate, expected answer —
//  you have used today's free quotes — as a fault, and says "couldn't save
//  quote" about a database working exactly as designed.
//

import Foundation
import Supabase

extension Error {
    /// The Postgres error underneath, if this failure came from one.
    private var postgrest: PostgrestError? { self as? PostgrestError }

    /// True when the database refused a write because the account has spent its
    /// free quotes for the day.
    ///
    /// Matched two ways on purpose. `PT402` is PostgREST's convention for "give
    /// this one a 402", and is what a current gateway reports; the message is
    /// the marker the trigger raises and survives a gateway that maps the code
    /// to a plain 500. Getting this wrong in the false direction shows an error
    /// where the paywall belongs, which is the difference between a dead end
    /// and an offer.
    var isQuoteAllowanceExhausted: Bool {
        if let postgrest {
            return postgrest.code == "PT402"
                || postgrest.message.contains("quote_allowance_exhausted")
        }
        return localizedDescription.contains("quote_allowance_exhausted")
    }

    /// True when the database has no such function.
    ///
    /// `PGRST202` is PostgREST failing to find it in the schema cache;
    /// `42883` is Postgres' own undefined_function. Only these two mean "this
    /// database predates the RPC" — every other error means the RPC exists and
    /// said no, which is a very different thing to do next.
    var isMissingDatabaseFunction: Bool {
        guard let postgrest else { return false }
        return postgrest.code == "PGRST202" || postgrest.code == "42883"
    }
}
