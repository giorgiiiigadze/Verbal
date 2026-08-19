//
//  ThreadConnector.swift
//  Verbal
//
//  The rail and elbow that tie a run of quotes to the client above them.
//

import SwiftUI

/// The thread line beside one quote: a vertical rail with a rounded elbow that
/// branches into the card at its mid-height.
///
/// The rail is drawn to the full height it's given (the card plus its vertical
/// padding), so stacking these leaves the rail unbroken between siblings. The
/// last quote gets no continuation below its elbow — the thread ends where it
/// turns in, the way the final reply closes a comment chain.
/// Not private: `ClientThread` draws it, and the clients feed lays it out.
struct ThreadConnector: Shape {
    var isLast: Bool

    /// Width of the connector column, and so where the branch meets the card.
    static let gutter: CGFloat = 24

    /// Where the rail runs, measured from the leading edge of the column. The
    /// node is drawn on top of the path at this same x — see `ClientThread`.
    static let railX: CGFloat = 7
    /// Radius of that node, so the branch can start clear of it rather than
    /// running out from under it.
    static let nodeRadius: CGFloat = 3.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let railX = Self.railX
        let midY = rect.midY

        // Straight lines and a right angle, not a rounded elbow peeling off a
        // curve. The rail is a spine with a node on it for each quote and a
        // short arm out to the card — the shape a timeline has, where the
        // curve made it a comment thread.
        path.move(to: CGPoint(x: railX, y: rect.minY))
        // The rail carries through the siblings still to come, and stops at the
        // last node rather than running on to nothing.
        path.addLine(to: CGPoint(x: railX, y: isLast ? midY : rect.maxY))

        path.move(to: CGPoint(x: railX + Self.nodeRadius, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        return path
    }
}
