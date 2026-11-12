//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusManager+RegistrationPlace.swift
//
//  The focus ring is the order in which controls register, which is the
//  order they are drawn in. A pulled column (SCROLL-FIT, `StackPulledColumn.swift`)
//  draws its anchored row first, then the rows below it, then the rows above
//  it, nearest first, and last the children off the band: so the controls
//  above its anchor registered after the ones below, and Tab ran down the
//  screen, jumped back up and ran down again. The rows above are filed at the
//  place the column's first row would have taken instead, so the ring is the
//  order of the rows, as an eager column's is.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Where registrations were being filed in each section, at one moment of a
/// walk: what ``FocusManager/registering(at:_:)`` files the elements of rows
/// drawn later at, so they come before what was drawn since.
package struct FocusRegistrationMark {
    fileprivate let places: [ObjectIdentifier: Int]
    /// How many each section held, and whether it was filing at a place.
    fileprivate let counts: [ObjectIdentifier: (count: Int, isPlaced: Bool)]
}

extension FocusManager {
    /// Where the next registration in each section would be filed now.
    package func registrationMark() -> FocusRegistrationMark {
        var places: [ObjectIdentifier: Int] = [:]
        var counts: [ObjectIdentifier: (count: Int, isPlaced: Bool)] = [:]
        for section in sections {
            places[ObjectIdentifier(section)] = section.registrationPlace ?? section.focusables.count
            counts[ObjectIdentifier(section)] = (section.focusables.count, section.registrationPlace != nil)
        }
        return FocusRegistrationMark(places: places, counts: counts)
    }

    /// Takes back every registration made since `mark`, for a subtree drawn
    /// again in the same walk (`RenderWalkCheckpoint.rewind(context:)`): the
    /// second drawing files its controls afresh, in its own order. Kept, a
    /// control the first drawing alone drew stayed in the ring, and one both
    /// drew kept the first's place — after the scroll view moved to reveal a
    /// control, the row that came on screen above the rest was filed after
    /// them all.
    package func rewindRegistrations(to mark: FocusRegistrationMark) {
        for section in sections {
            let key = ObjectIdentifier(section)
            guard let was = mark.counts[key], let place = mark.places[key] else {
                section.unfile(0..<section.focusables.count)
                continue
            }
            let filed = section.focusables.count - was.count
            if filed > 0 { section.unfile(place..<(place + filed)) }
            section.registrationPlace = was.isPlaced ? place : nil
        }
    }

    /// Runs `body` filing every registration it makes at `mark`, in the order
    /// it makes them, ahead of what registered after the mark was taken. What
    /// was being filed at a place before is filed after what `body` filed
    /// there, so a column inside a row drawn this way files its own rows in
    /// order too. A section first seen in `body` is filed in at its end.
    package func registering<T>(at mark: FocusRegistrationMark, _ body: () -> T) -> T {
        let saved = sections.map { (section: $0, place: $0.registrationPlace, count: $0.focusables.count) }
        // A section the mark does not know was made after it — a walk files its
        // sections as their first controls register, so at a column's mark
        // the page's first section may not exist yet — and everything in it
        // was filed after the mark: its place is its start.
        for section in sections {
            section.registrationPlace = mark.places[ObjectIdentifier(section)] ?? 0
        }
        defer {
            for entry in saved {
                let filed = entry.section.focusables.count - entry.count
                entry.section.registrationPlace = entry.place.map { $0 + filed }
            }
        }
        return body()
    }
}
