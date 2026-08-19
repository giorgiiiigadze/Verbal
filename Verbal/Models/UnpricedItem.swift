//
//  UnpricedItem.swift
//  Verbal
//
//  A line the extraction couldn't price. The sheet that offers these to the
//  rate card is not their only reader — the recording screen counts them.
//

import Foundation

/// A line the extraction couldn't price, as a candidate rate-card entry.
struct UnpricedItem: Identifiable {
    let id: UUID
    let name: String
    let unit: String?
    let type: String
}
