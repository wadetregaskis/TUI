//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeldPress+Widening.swift
//
//  A drag kept to a bordered container's interior that goes well past it
//  widens to the scope the container sits in (A-TEXT2-1, option 2: built
//  2026-10-24 as an experiment for the owner to try). All of the rule but
//  the two stored properties it moves is here, so it can be tuned, or taken
//  out, in one place.
//
//  Created by Wade Tregaskis
//  License: MIT

extension HeldPress {
    /// How many rows outside the rectangle it keeps to a drag may go and stay
    /// kept to it: the border's own row and two beyond it. A drag down to
    /// "the end of a card" overshoots its bottom border as a matter of course,
    /// by a row or two, and that must not throw the selection out to the
    /// page; three rows beyond the border is a drag that meant to leave, yet
    /// still few enough to reach below a card near the screen's foot.
    /// (A-TEXT2-1: an experiment, for the owner to feel.)
    static let wideningRows = 3

    /// How many columns outside the rectangle a drag may go and stay kept to
    /// it: the border's own column and five beyond. Twice ``wideningRows``,
    /// as a cell is about half as wide as it is tall — the same distance on
    /// the screen — and a drag to a line's end overshoots sideways as freely
    /// as one to a card's end does downward.
    static let wideningColumns = 6

    /// Widens the selection's clip, a scope at a time, while `pointer` is
    /// further outside it than ``wideningRows`` or ``wideningColumns`` allow.
    /// One way: a pointer that comes back inside leaves it widened, so the
    /// selection does not flicker back mid-gesture.
    ///
    /// Asked on each drag step, never per frame; with nothing to widen to —
    /// every drag not begun in a bordered container's interior — it is one
    /// test of an empty slice.
    func widen(toward pointer: ScreenSelection.Point) {
        guard !widenings.isEmpty else { return }
        var widened = false
        while let next = widenings.first, Self.isPast(clip, pointer) {
            clip = next
            widenings.removeFirst()
            widened = true
        }
        if widened { selection?.widen(to: clip) }
    }

    /// Whether `pointer` is outside `rect` by more than ``wideningRows`` rows
    /// or ``wideningColumns`` columns. The cell just outside counts as 1 —
    /// for an interior, that is the border itself.
    static func isPast(_ rect: ScreenSelection.Rect, _ pointer: ScreenSelection.Point) -> Bool {
        func outside(_ value: Int, _ start: Int, _ length: Int) -> Int {
            value < start ? start - value : max(0, value - (start + length - 1))
        }
        return outside(pointer.y, rect.y, rect.height) > wideningRows
            || outside(pointer.x, rect.x, rect.width) > wideningColumns
    }
}
