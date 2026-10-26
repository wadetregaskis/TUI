//  🖥️ TUI — A Terminal UI framework for Swift
//  KittyGraphics+ClassicPlacements.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drawing an image at the cursor

extension KittyGraphics {

    /// The escape that draws image `id` at the cursor, as a **classic**
    /// placement: outside the cell grid, from the cursor cell's top-left
    /// corner, at the image's own pixel size, cropped to the top-left
    /// `sourceWidth` × `sourceHeight` pixels of it.
    ///
    /// The other half of the protocol from ``placement(id:columns:rows:)``,
    /// and NOT a substitute for it. A virtual placement is drawn by cells and
    /// so is clipped, scrolled and covered with them; this one is drawn where
    /// the cursor was when it was sent and stays there until it is deleted —
    /// whatever is drawn over it, whatever scrolls. It is for the one picture
    /// a cell cannot carry: a line thinner than a row, along the boundary
    /// between two (`Documentation/Historical/Investigations/Thin lines between
    /// rows with Kitty graphics (2026-10-08).md`).
    /// Whoever sends one owns keeping it where it belongs, and deleting it.
    ///
    /// The keys, and why each is spelled:
    ///
    /// - `p` always: the placement's own id, so that ``deletePlacement(id:placement:)``
    ///   can take away exactly this one, and so that sending it again with
    ///   the same `(i, p)` replaces it in place rather than adding a second
    ///   (the spec says without flicker; measured on Ghostty 1.3.1 and iTerm2
    ///   3.7.3 at 60 Hz).
    /// - `x=0,y=0,w,h` and no `c`/`r`: drawn at native size and cropped,
    ///   because hosts disagree on what `c` and `r` do to a picture that does
    ///   not fit them (the spec letterboxes, Ghostty and Konsole stretch), and
    ///   every host read crops.
    /// - `C=1`: the cursor stays where it was. TUI positions every write
    ///   with CUP anyway; this removes the scroll a placement on the bottom row
    ///   would otherwise cause.
    /// - `z`, never 0: iTerm2 draws `z=0` under the text and `z=-1` over a
    ///   cell's fill (its Metal passes; measured on 3.7.3), and the spec
    ///   orders `0` with neither, so a placement that asks for 0 is refused.
    /// - `q=2`, as on every command this framework writes outside the startup
    ///   handshake: an answer would arrive on stdin as typing.
    ///
    /// - Returns: the escape, or `""` for a request the protocol cannot
    ///   express: an id outside `1...maximumImageID`, a placement id of 0
    ///   (the protocol's word for "none"), a non-positive crop, or `z == 0`.
    package static func classicPlacement(
        id: ImageID, placement: UInt32, sourceWidth: Int, sourceHeight: Int, z: Int32
    ) -> String {
        guard id > 0, id <= maximumImageID, placement > 0, sourceWidth > 0, sourceHeight > 0, z != 0
        else { return "" }
        return "\u{1B}_Ga=p,i=\(id),p=\(placement),x=0,y=0,w=\(sourceWidth),h=\(sourceHeight),C=1,z=\(z),q=2\u{1B}\\"
    }

    /// The escape that deletes one placement of image `id`, by its placement
    /// id, and keeps the image's data in the store.
    ///
    /// Lower-case `d=i`, against ``delete(id:)``'s `d=I`: the image is
    /// placed again later without being sent again (measured on both hosts
    /// in `hairline_probe.py`'s Q6), so its pixels stay.
    package static func deletePlacement(id: ImageID, placement: UInt32) -> String {
        guard id > 0, id <= maximumImageID, placement > 0 else { return "" }
        return "\u{1B}_Ga=d,d=i,i=\(id),p=\(placement),q=2\u{1B}\\"
    }
}

// MARK: - Whether this terminal draws a line between rows

extension KittyGraphics {

    /// Whether the terminal painting this app's output draws the line a
    /// `.hairline` list separator is — a classic placement a pixel or two
    /// thick, on the boundary between two rows — published from
    /// `TerminalClient.applyGraphicsSupport()`.
    ///
    /// A different answer from ``isSupported``, which is about VIRTUAL
    /// placements and is asked of the terminal. Nothing asks this one: a host
    /// that answers the handshake `OK` may still draw a classic placement in a
    /// layer the line cannot use (Konsole hides `z<0` under every painted
    /// cell), or in a pixel unit no query reveals (iTerm2 3.7.3). So it is a
    /// table of hosts somebody measured, ANDed with the handshake: Ghostty
    /// today, and only where the terminal reports its cell's pixel size. See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "A line on a
    /// row boundary".
    ///
    /// Read by the list as it decides what a separator costs: where this is
    /// `true`, an `.automatic` separator look is a hairline, which takes no
    /// row; elsewhere it is a rule line of its own. **Defaults to `false`**,
    /// so a list renders as it always has wherever nothing answered.
    public static var isHairlineSupported: Bool {
        get { taskHairlineSupported ?? processHairlineSupported }
        set { processHairlineSupported = newValue }
    }

    /// `nonisolated(unsafe)` for the reason ``isSupported`` gives: written
    /// during startup, before the render loop exists, and only read after.
    nonisolated(unsafe) private static var processHairlineSupported = false

    /// A task-scoped pin, bound by ``withHairlineSupport(_:operation:)``.
    @TaskLocal private static var taskHairlineSupported: Bool?

    /// Runs `operation` with ``isHairlineSupported`` pinned on this task
    /// only, for the reason ``withSupport(_:compression:operation:)`` is
    /// task-local: tests run in parallel.
    @discardableResult
    public static func withHairlineSupport<T>(_ supported: Bool, operation: () throws -> T) rethrows -> T {
        try $taskHairlineSupported.withValue(supported, operation: operation)
    }
}
