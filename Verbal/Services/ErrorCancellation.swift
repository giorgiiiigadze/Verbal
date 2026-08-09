//
//  ErrorCancellation.swift
//  Verbal
//
//  Telling "this was called off" apart from "this went wrong".
//
//  SwiftUI cancels a `.task` the moment its view goes away — tapping a row,
//  switching tab, opening a sheet — and any request still in flight throws for
//  that reason. Treated as a failure it puts an error on screen for the
//  ordinary act of tapping something, which reads as random because it depends
//  on whether the user touched anything during the fraction of a second a
//  fetch takes.
//

import Foundation

extension Error {
    /// True when this error is a cancellation rather than a genuine failure.
    ///
    /// It arrives in more than one costume: straight from Swift concurrency as
    /// `CancellationError`, or as `URLError.cancelled` once it has been through
    /// URLSession — which is the shape it takes coming back out of Supabase.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError { return urlError.code == .cancelled }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
