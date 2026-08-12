//
//  TradePresets.swift
//  Verbal
//
//  The jobs offered during onboarding, per trade, so the rate card isn't empty
//  on the first quote. An empty card is why early quotes come back full of
//  "Needs price", and a tradesperson who has to type their prices before the app
//  has done anything for them mostly doesn't.
//
//  Priced by the job rather than by the hour, deliberately: quoting a customer a
//  job price is what this app is for, and an hourly rate can't price a line on
//  its own. The two exceptions — fault finding, prep — are the work that
//  genuinely is sold by the hour.
//
//  Named the way a British trade names them. Worth revisiting per market: a
//  translated "consumer unit" reads as a foreign app.
//

import Foundation

enum TradePresets {
    struct Job: Hashable, Identifiable {
        let name: String
        let unit: String
        var id: String { name }
    }

    /// Every one of these is work performed, so they all save as `labor`. A
    /// material's price belongs to a supplier and changes without warning; these
    /// are the numbers the user themselves decides.
    static let type = "labor"

    /// A trade that isn't on the list still gets asked, just generically: every
    /// trade sells its time and its turning up, whatever else it sells. Empty
    /// only when the question was skipped, where there is nothing to go on.
    static func jobs(for trade: String) -> [Job] {
        let name = trade.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }
        return table[name] ?? generic
    }

    private static let generic: [Job] = [
        Job(name: "Call-out fee", unit: "job"),
        Job(name: "Hourly rate", unit: "hour"),
        Job(name: "Day rate", unit: "day"),
    ]

    private static let table: [String: [Job]] = [
        "Electrician": [
            Job(name: "Add a double socket", unit: "each"),
            Job(name: "Replace a light fitting", unit: "each"),
            Job(name: "Fit downlights", unit: "each"),
            Job(name: "Replace consumer unit", unit: "job"),
            Job(name: "Rewire a room", unit: "job"),
            Job(name: "EV charger install", unit: "each"),
            Job(name: "Fault finding", unit: "hour"),
            Job(name: "Day rate", unit: "day"),
        ],
        "Plumber": [
            Job(name: "Replace a toilet", unit: "each"),
            Job(name: "Fit a basin", unit: "each"),
            Job(name: "Fit a mixer tap", unit: "each"),
            Job(name: "Install a shower", unit: "each"),
            Job(name: "Swap a radiator", unit: "each"),
            Job(name: "Fix a leak", unit: "hour"),
            Job(name: "Unblock a drain", unit: "job"),
            Job(name: "Day rate", unit: "day"),
        ],
        "Carpenter": [
            Job(name: "Hang a door", unit: "each"),
            Job(name: "Fit skirting", unit: "m"),
            Job(name: "Lay wood flooring", unit: "m²"),
            Job(name: "Fit kitchen units", unit: "each"),
            Job(name: "Build fitted wardrobe", unit: "job"),
            Job(name: "Build shelving", unit: "job"),
            Job(name: "Day rate", unit: "day"),
        ],
        "Tiler": [
            Job(name: "Wall tiling", unit: "m²"),
            Job(name: "Floor tiling", unit: "m²"),
            Job(name: "Remove old tiles", unit: "m²"),
            Job(name: "Tanking / waterproofing", unit: "m²"),
            Job(name: "Grouting", unit: "m²"),
            Job(name: "Fit trim and edging", unit: "m"),
            Job(name: "Day rate", unit: "day"),
        ],
        "Painter": [
            Job(name: "Emulsion a room", unit: "job"),
            Job(name: "Paint walls", unit: "m²"),
            Job(name: "Paint ceiling", unit: "m²"),
            Job(name: "Gloss a door", unit: "each"),
            Job(name: "Hang wallpaper", unit: "m²"),
            Job(name: "Exterior painting", unit: "m²"),
            Job(name: "Filling and prep", unit: "hour"),
            Job(name: "Day rate", unit: "day"),
        ],
        "Plasterer": [
            Job(name: "Skim a wall", unit: "m²"),
            Job(name: "Skim a ceiling", unit: "m²"),
            Job(name: "Plasterboard / dry lining", unit: "m²"),
            Job(name: "Rendering", unit: "m²"),
            Job(name: "Patch repair", unit: "job"),
            Job(name: "Fit coving", unit: "m"),
            Job(name: "Day rate", unit: "day"),
        ],
        "Builder": [
            Job(name: "Blockwork", unit: "m²"),
            Job(name: "Knock through with lintel", unit: "job"),
            Job(name: "Concrete slab", unit: "m²"),
            Job(name: "Foundations", unit: "m"),
            Job(name: "Strip out / demolition", unit: "job"),
            Job(name: "Day rate", unit: "day"),
            Job(name: "Labourer day rate", unit: "day"),
        ],
        "Roofer": [
            Job(name: "Re-roof", unit: "m²"),
            Job(name: "Replace broken tiles", unit: "each"),
            Job(name: "Flat roof covering", unit: "m²"),
            Job(name: "Guttering", unit: "m"),
            Job(name: "Re-bed ridge tiles", unit: "m"),
            Job(name: "Chimney repointing", unit: "job"),
            Job(name: "Leak repair", unit: "job"),
            Job(name: "Day rate", unit: "day"),
        ],
        "Landscaper": [
            Job(name: "Lay turf", unit: "m²"),
            Job(name: "Patio / paving", unit: "m²"),
            Job(name: "Decking", unit: "m²"),
            Job(name: "Fencing", unit: "m"),
            Job(name: "Driveway", unit: "m²"),
            Job(name: "Garden clearance", unit: "job"),
            Job(name: "Planting", unit: "job"),
            Job(name: "Day rate", unit: "day"),
        ],
    ]
}
