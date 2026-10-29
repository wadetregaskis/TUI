//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalImageStore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Any signature at all

/// A signature the store can compare without knowing what it signs.
///
/// A picture's signature (``TerminalImageSignature``) and a gradient's
/// (`GradientImageSignature`) have nothing in common but the one thing the
/// store needs — equality — so the store holds this and asks that. Erasing
/// the type here, rather than making the store generic or the signatures an
/// enum, keeps each caller's signature its own ordinary struct: every field
/// that decides a picture is still a typed, `Equatable` field on a type that
/// says what it is for.
///
/// `@usableFromInline`, with its fields, and its initializer `@inlinable`:
/// ``TerminalImageStore/placeholderRows(token:signature:columns:rows:pixels:)``
/// erases its caller's signature into one of these in the caller's module,
/// where the signature's type is known (see that method), and no module but
/// this one can name it.
@usableFromInline
struct AnyImageSignature: Equatable {
    @usableFromInline let value: Any
    @usableFromInline let equals: (Any) -> Bool

    @inlinable
    init<S: Equatable>(_ value: S) {
        self.value = value
        self.equals = { ($0 as? S) == value }
    }

    @usableFromInline
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.equals(rhs.value) }
}

// MARK: - Where the store files a signature

/// A signature the store can file, so that finding a picture among many does
/// not mean comparing it against every picture the terminal holds.
///
/// Not a hash of the whole signature. Most of what decides a picture (a paint,
/// a configuration, a colour mode) is `Equatable` and not `Hashable`, and
/// making it hashable would add a conformance to about ten public types for
/// one internal lookup. ``storeBucket`` is a cheap projection of some of the fields
/// `==` compares instead. The store files each image under its bucket and its
/// cell box, and compares a request only against the images filed there.
///
/// The one rule: **two signatures that compare equal give equal buckets.**
/// Break it and a view asking for a picture the terminal already holds looks
/// in the wrong place, transmits a second copy, and shares nothing. Built from
/// fields that `==` compares with their own synthesised equality, it holds by
/// construction. A field left out only makes a bucket hold more pictures, and
/// a bucket every picture shares makes each lookup a search of them all.
///
/// `@usableFromInline` for the same reason as ``AnyImageSignature``: the
/// inlinable `placeholderRows` is generic over it.
@usableFromInline
package protocol ImageStoreSignature: Equatable {
    associatedtype StoreBucket: Hashable
    /// Some of the fields `==` compares, as a key the store can hash.
    var storeBucket: StoreBucket { get }
}

// MARK: - The images this app has put in the terminal

/// Owns every image TUI has transmitted to the terminal, and is the only
/// thing that deletes one.
///
/// A Kitty image is **retained**: it is transmitted once, given an id, and
/// then drawn as many times as you like by writing cells that name that id.
/// That is what makes the feature affordable — a picture costs its bytes once
/// rather than once a frame — and it is also the catch, because those bytes
/// now live in the terminal and nothing in the terminal will ever free them.
/// A view that renders an image and goes away has leaked until this store
/// deletes it.
///
/// So there is exactly one owner, keyed by the view's identity path, and it
/// answers three questions:
///
/// - **What do I draw?** ``placeholderRows(token:signature:columns:rows:pixels:)``
///   returns the cells — transmitting first if this is a picture the terminal
///   does not have, and sending a placement alone if it is one it does at a
///   size it was not told about.
/// - **What do I still owe the terminal?** ``takePending()`` hands back the
///   escapes that have to reach it before the frame those cells are in, and
///   ``takeDeletes()`` the deletes that go after them.
/// - **What can go?** ``release(token:)``, from the view's disappear handler.
///
/// ## One picture, many views
///
/// Two views asking for the same picture in the same box get the same image:
/// the store transmits once and hands both the same cells, and the terminal
/// keeps the bytes until the LAST of them lets go. A list of one icon, or a
/// column of progress bars sharing one gradient, costs one transmission
/// rather than one per row. Sharing is by content — a signature and a cell
/// box that compare equal — so it never depends on which view asked first,
/// and a view that moves on to a different picture leaves the shared one for
/// the others rather than deleting it under them. Finding the image to share
/// does not compare the request against every image the terminal holds; see
/// ``ImageStoreSignature``.
///
/// ## Why the escapes are queued rather than written
///
/// They are produced during the render pass, by a `Renderable` that has a
/// `RenderContext` and no terminal — and must be *written* before the frame
/// that refers to them, which is a different moment. Queuing here and
/// draining at `beginFrame` is the seam. It also means a measure pass that
/// renders (a Card measuring its container, a Table probing a multi-line
/// cell) transmits nothing, because it never asks.
///
/// ## Why a picture that changes is never blank
///
/// A view that moves on to a different picture — another photo, or the same
/// one at a resolution its new box needs — gets it under a FRESH id, and its
/// old image is deleted only after the frame's cells stop naming it
/// (``takeDeletes()``, which the run loop writes inside the frame's
/// synchronized-update hold). Until 2026-10-27 the old image was deleted
/// first and the new one sent on the same id, ahead of the hold: the picture
/// was blank for as long as the new bytes took to travel — 2.5 s for a
/// 720×550 photo while a split view's divider was dragged — and then the new
/// picture drew for a frame in the old cells, in the old layout. Now the old
/// picture stays on screen until the cells naming the new one replace it, in
/// one held update.
///
/// ## Isolation
///
/// `@unchecked Sendable`, exactly as `LifecycleManager` is, and for the same
/// reason: it is reached from `Renderable.renderToBuffer`, which is not
/// actor-isolated, and from the run loop, which is — but both run on the run
/// loop's own thread, one render pass at a time. There is no concurrency here
/// to check; there is a compiler that cannot see that.
@usableFromInline
package final class TerminalImageStore: @unchecked Sendable {

    /// One image in the terminal, the cells that draw it, and who is drawing
    /// them.
    private struct Image {
        let id: KittyGraphics.ImageID
        let signature: AnyImageSignature
        /// Where the image is filed: its signature's bucket, and the cell box
        /// declared to the terminal, so a box-only change can be spotted and
        /// answered with a placement alone.
        var slot: Slot
        /// When the image was put in the terminal, counting up. Two images can
        /// hold one picture in one box (``sharedImage(of:in:)`` says how), and
        /// a view that asks for that picture then shares the older one. A
        /// shutdown deletes in this order too (``releaseAll()``).
        let arrival: Int
        /// The placeholder cells, which are a function of the id and the box.
        var cells: [String]
        /// The tokens currently drawing this image. Empty means nobody, and
        /// nobody means deleted — an image is never kept on the chance that
        /// someone comes back for it.
        var holders: Set<String>
    }

    /// Where an image is filed: its signature's
    /// ``ImageStoreSignature/storeBucket`` and its cell box. Two requests for
    /// one picture in one box always come to the same slot, and a slot almost
    /// always holds one image.
    private struct Slot: Hashable {
        let bucket: AnyHashable
        let columns: Int
        let rows: Int
    }

    private var images: [KittyGraphics.ImageID: Image] = [:]
    /// The images filed in each slot.
    private var slots: [Slot: [KittyGraphics.ImageID]] = [:]
    /// Which image each token is drawing.
    private var entries: [String: KittyGraphics.ImageID] = [:]
    /// The images each holding token keeps (``hold(picturesIn:for:)``): a
    /// token that draws none of them itself.
    private var holds: [String: Set<KittyGraphics.ImageID>] = [:]

    /// What a frost made of everything behind it where a picture was there
    /// (``backdrop(pixels:columns:rows:pixelsPerCell:)``), newest last: pictures of no view,
    /// never sent themselves, which their tinted copies are made from.
    private var backdrops: [(key: BackdropKey, id: KittyGraphics.ImageID)] = []

    /// A backdrop's pixels and its box, which say everything about it: a frost
    /// that makes the same one again, frame after frame, is given the same id.
    private struct BackdropKey: Hashable {
        let columns: Int
        let rows: Int
        let pixels: [UInt8]
    }

    /// How many backdrops are kept. A glass fading in makes one at each of its
    /// tints only if what is behind changes; past this, the oldest goes, with
    /// its copies.
    static let backdropLimit = 6

    /// The box each image's second placement was last given
    /// (``scaledPlaceholderRows(of:columns:rows:)``), so a size it already has
    /// is not sent again.
    private var scaledBoxes: [KittyGraphics.ImageID: (columns: Int, rows: Int)] = [:]
    private var pending = ""
    /// The deletes owed after the frame's cells (``takeDeletes()``).
    private var deletes = ""
    /// The ids ``deletes`` names, in the order they were let go. Not handed
    /// out again until the deletes are taken: a picture sent on one before
    /// then would be deleted by them.
    private var retiring: [KittyGraphics.ImageID] = []
    /// Copies of the pictures, changed for a translucent layer over them.
    private var derivedImages = DerivedImages()
    private var nextID: KittyGraphics.ImageID = 1
    /// The next image's arrival.
    private var nextArrival = 0

    /// How many images this app currently has in the terminal. For tests and
    /// diagnostics — a number that only ever grows is the leak this type
    /// exists to prevent.
    var imageCount: Int { images.count }

    /// Counts every image put in the terminal or taken out of it, so the run
    /// loop can tell after a frame whether ``farewell(fitting:)`` changed
    /// without spelling it again.
    package var generation: Int { _generation }

    /// ``generation``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _generation = 0

    // MARK: - Drawing

    /// The placeholder rows for `token`'s image, transmitting it first if the
    /// terminal does not already have exactly this picture at exactly this
    /// size.
    ///
    /// - Parameters:
    ///   - token: The owning view's identity. One image per token; a second
    ///     call with a different `signature` moves the token to the new
    ///     picture and frees the old one if nobody else is drawing it, which
    ///     is what stops a resize leaking an image a frame.
    ///   - signature: Everything that decides the picture's content — and
    ///     deliberately nothing about where it goes, so a move or a resize
    ///     that resamples to the same resolution costs a placement rather
    ///     than a re-transmission. Two tokens whose signatures compare equal
    ///     share one image.
    ///   - columns: Width of the placement, in cells.
    ///   - rows: Height of the placement, in cells.
    ///   - pixels: 8-bit pixel bytes and their format, row-major, at the
    ///     resolution the signature names. **Only evaluated when the terminal
    ///     does not already hold this picture** — it is a resample of the
    ///     decoded image and megabytes of it, and the common case by a wide
    ///     margin is that nothing has changed since last frame.
    /// - Returns: the rows, or `nil` for a request the protocol cannot express
    ///   — at which point the caller draws the picture out of glyphs, as it
    ///   always has.
    ///
    /// Generic in name only: all it does with `Signature` is erase it, here,
    /// and hand the rest to the non-generic
    /// ``placeholderRows(token:signature:bucket:columns:rows:pixels:)``.
    /// `@inlinable`, so the erasure happens in the caller's module, specialised
    /// for its signature: a picture's (`_ImageCore`, TUIBitmaps since module
    /// split step B5c) runs once a frame for every image drawn with terminal
    /// graphics, and a call to a generic method in another module would run
    /// unspecialised, the erasure through the signature's metadata. The class,
    /// ``AnyImageSignature`` and ``ImageStoreSignature`` are
    /// `@usableFromInline` for it: an `@inlinable` member of a type that is
    /// only `package` is not serialized for another module to inline.
    @inlinable
    package func placeholderRows<Signature: ImageStoreSignature>(
        token: String, signature: Signature,
        columns: Int, rows: Int,
        pixels: () -> (bytes: [UInt8], format: KittyGraphics.PixelFormat, width: Int, height: Int)
    ) -> [String]? {
        placeholderRows(
            token: token, signature: AnyImageSignature(signature), bucket: { AnyHashable(signature.storeBucket) },
            columns: columns, rows: rows, pixels: pixels)
    }

    /// ``placeholderRows(token:signature:columns:rows:pixels:)``, with the
    /// signature already erased (`wanted`) and the bucket it files under asked
    /// for only when the picture is not this token's already (`bucket`, the
    /// signature's ``ImageStoreSignature/storeBucket``).
    @usableFromInline
    func placeholderRows(
        token: String, signature wanted: AnyImageSignature, bucket: () -> AnyHashable,
        columns: Int, rows: Int,
        pixels: () -> (bytes: [UInt8], format: KittyGraphics.PixelFormat, width: Int, height: Int)
    ) -> [String]? {
        guard columns > 0, rows > 0,
            columns <= KittyGraphics.maximumCellExtent,
            rows <= KittyGraphics.maximumCellExtent
        else { return nil }

        // The token's own image, if it still is this picture.
        if let id = entries[token], let image = images[id], image.signature == wanted {
            if image.slot.columns == columns, image.slot.rows == rows {
                return image.cells
            }
            // The same picture in a DIFFERENT box. Alone on the image, this
            // needs no bytes: an `a=p` replaces the placement (its id says
            // which, `KittyGraphics.placement`) and the terminal refits the
            // picture to the new rectangle. Without
            // this case every step of a resize drag ran delete + transmit +
            // place — megabytes, per step, to end up with the pixels already
            // in the store. Shared, the box belongs to the others too, so the
            // token moves on to an image of its own instead.
            if image.holders == [token] {
                let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows)
                guard !cells.isEmpty else { return nil }
                pending += KittyGraphics.placement(id: id, columns: columns, rows: rows)
                refile(id, in: Slot(bucket: image.slot.bucket, columns: columns, rows: rows), cells: cells)
                // Its copies were placed in the old box; they are made again
                // when next asked for, from a small copy of the new size.
                deleteCopies(of: id)
                derivedImages.resize(id, columns: columns, rows: rows)
                return cells
            }
        }

        // Somebody else's image of exactly this picture in exactly this box:
        // share it, and let go of whatever this token was drawing before.
        let slot = Slot(bucket: bucket(), columns: columns, rows: rows)
        if let id = sharedImage(of: wanted, in: slot) {
            if entries[token] != id { release(token: token) }
            // `release` frees only an image this token was drawing, and this
            // one was not, so it is still here. Checked rather than assumed.
            guard images[id] != nil else { return nil }
            images[id]?.holders.insert(token)
            entries[token] = id
            return images[id]?.cells
        }

        // A picture the terminal does not have, sent under a FRESH id. The
        // token's previous image is let go — deleted, if this was its only
        // holder — but its delete waits for the frame's cells
        // (``takeDeletes()``): the old picture stays on screen until the
        // cells naming the new one replace it, rather than going blank while
        // the new bytes travel. Never re-transmitted over the old id, either,
        // which is documented to replace it but measured on one terminal of
        // five; a fresh id never has to find out.
        if let previous = entries[token], images[previous] != nil {
            letGo(of: previous, by: token)
            entries.removeValue(forKey: token)
        }
        let id = claimID()
        let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows)
        guard !cells.isEmpty else { return nil }

        let payload = pixels()
        // Deflated where the terminal said it would take it — a photograph
        // gains a little, a gradient rendered as pixels gains an order of
        // magnitude — and raw everywhere else. See ``KittyGraphics/isCompressionSupported``.
        let transmit = KittyGraphics.transmit(
            pixels: payload.bytes, format: payload.format,
            width: payload.width, height: payload.height, id: id,
            compressed: KittyGraphics.isCompressionSupported)
        guard !transmit.isEmpty else { return nil }
        pending += transmit
        pending += KittyGraphics.placement(id: id, columns: columns, rows: rows)
        derivedImages.remember(id, columns: columns, rows: rows, pixels: payload)
        file(Image(id: id, signature: wanted, slot: slot, arrival: nextArrival, cells: cells, holders: [token]))
        nextArrival += 1
        entries[token] = id
        return cells
    }

    // MARK: - Derived copies

    /// `cell` of a picture, re-pointed at the picture changed by `transform` —
    /// transmitting that copy first if the terminal does not have it — or `nil`
    /// for a picture this store did not put there.
    ///
    /// For a translucent layer over a picture: what the cells under it draw
    /// is the picture with the layer already applied (`Terminal graphics
    /// protocols.md` §14).
    package func derived(
        _ cell: KittyGraphics.PlaceholderCell, by transform: ImageTransform
    ) -> KittyGraphics.PlaceholderCell? {
        // A copy's cell — a faded picture under a veil — is copied again from the
        // picture itself, by its transform and then this one.
        if images[cell.id] == nil, let origin = derivedImages.origin(of: cell.id) {
            return derived(
                KittyGraphics.PlaceholderCell(id: origin.source, row: cell.row, column: cell.column),
                by: origin.transform.followed(by: transform))
        }
        guard images[cell.id] != nil || isBackdrop(cell.id) else { return nil }
        if let copy = derivedImages.existingCopy(of: cell.id, by: transform) {
            return KittyGraphics.PlaceholderCell(id: copy, row: cell.row, column: cell.column)
        }
        let copyID = claimID()
        guard let made = derivedImages.make(of: cell.id, by: transform, as: copyID) else { return nil }
        pending += made.escapes
        // After the frame's cells, as every delete: one still names it.
        if let evicted = made.evicted { retire(evicted) }
        return KittyGraphics.PlaceholderCell(id: copyID, row: cell.row, column: cell.column)
    }

    /// The colour `cell` of a picture shows changed by `transform`, on
    /// average: what a glyph drawn over it stands on. Ask ``derived(_:by:)``
    /// first, which makes the copy.
    package func average(
        of cell: KittyGraphics.PlaceholderCell, by transform: ImageTransform
    ) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        if images[cell.id] == nil, let origin = derivedImages.origin(of: cell.id) {
            return derivedImages.average(
                of: origin.source, by: origin.transform.followed(by: transform), column: cell.column, row: cell.row)
        }
        return derivedImages.average(of: cell.id, by: transform, column: cell.column, row: cell.row)
    }

    // MARK: - Frost backdrops

    /// The id of a picture of what is behind a frost, `columns` × `rows` cells
    /// of `pixels` (RGBA, `pixelsPerCell` a cell — by default
    /// ``DerivedImages/pixelsAcross`` × ``DerivedImages/pixelsDown`` — already
    /// blurred): the pictures there and the cells between
    /// them, as one image, so the frost blurs across their edges
    /// (`FrameBuffer.frostBackdrop`). Never sent: the cells under the glass
    /// draw its copy tinted by the glass (``derived(_:by:)``), made from it as
    /// from any picture. The same pixels in the same box are the same id.
    package func backdrop(
        pixels: [UInt8], columns: Int, rows: Int,
        pixelsPerCell: (across: Int, down: Int) = (DerivedImages.pixelsAcross, DerivedImages.pixelsDown)
    ) -> KittyGraphics.ImageID? {
        guard columns > 0, rows > 0, pixelsPerCell.across > 0, pixelsPerCell.down > 0,
            pixels.count == columns * pixelsPerCell.across * rows * pixelsPerCell.down * 4
        else { return nil }
        let key = BackdropKey(columns: columns, rows: rows, pixels: pixels)
        if let index = backdrops.firstIndex(where: { $0.key == key }) {
            let known = backdrops.remove(at: index)
            backdrops.append(known)
            return known.id
        }
        let id = claimID()
        derivedImages.remember(
            id, columns: columns, rows: rows,
            pixels: (pixels, .rgba, columns * pixelsPerCell.across, rows * pixelsPerCell.down),
            pixelsPerCell: pixelsPerCell)
        backdrops.append((key, id))
        if backdrops.count > Self.backdropLimit {
            let oldest = backdrops.removeFirst()
            for copy in derivedImages.forget(oldest.id) { retire(copy) }
        }
        return id
    }

    /// Whether `id` is a frost's backdrop (``backdrop(pixels:columns:rows:pixelsPerCell:)``),
    /// already blurred: its copies are not blurred again.
    package func isBackdrop(_ id: KittyGraphics.ImageID) -> Bool {
        backdrops.contains { $0.id == id }
    }

    /// The small copy's pixels of `cell` of a picture or a copy — what a
    /// frost's backdrop takes for that cell (``DerivedImages/cellPixels(of:column:row:across:down:)``).
    package func cellPixels(
        of cell: KittyGraphics.PlaceholderCell, across: Int = DerivedImages.pixelsAcross,
        down: Int = DerivedImages.pixelsDown
    ) -> [UInt8]? {
        derivedImages.cellPixels(of: cell.id, column: cell.column, row: cell.row, across: across, down: down)
    }

    // MARK: - Scaled

    /// The cells that draw image `id` — a picture, or a copy of one — scaled
    /// to `columns` × `rows`, by a second placement of it (`p=2`) the cells
    /// name in their underline colour, so its own placement, and every cell
    /// that draws it, is untouched: what a navigation zoom draws a picture
    /// with as its rectangle grows or shrinks (`NavigationZoom`). The
    /// placement is sent when its box changes, and costs no pixels.
    package func scaledPlaceholderRows(
        of id: KittyGraphics.ImageID, columns: Int, rows: Int
    ) -> [String]? {
        guard images[id] != nil || derivedImages.isCopy(id) else { return nil }
        let cells = KittyGraphics.placeholderRows(id: id, columns: columns, rows: rows, placement: 2)
        guard !cells.isEmpty else { return nil }
        if scaledBoxes[id].map({ $0 != (columns, rows) }) ?? true {
            pending += KittyGraphics.placement(id: id, columns: columns, rows: rows, placement: 2)
            scaledBoxes[id] = (columns, rows)
        }
        return cells
    }

    /// The box image `id` — a picture, or a copy of one — is placed in, in
    /// cells: what its cells' rows and columns count across.
    package func placementBox(of id: KittyGraphics.ImageID) -> (columns: Int, rows: Int)? {
        if let image = images[id] { return (image.slot.columns, image.slot.rows) }
        return derivedImages.box(ofCopy: id)
    }

    // MARK: - Owning

    /// Gives back `token`'s image — to the terminal, if nobody else is
    /// drawing it.
    ///
    /// Called from the view's disappear handler, which is the only moment
    /// anything knows the picture is not coming back.
    package func release(token: String) {
        if let held = holds.removeValue(forKey: token) {
            for id in held { letGo(of: id, by: token) }
        }
        guard let id = entries.removeValue(forKey: token) else { return }
        letGo(of: id, by: token)
    }

    /// The rectangle of derived copy `copyID`'s pixels that its cell
    /// (`column`, `row`) draws, for laying that cell of it under a glyph (``DerivedImages``).
    package func pixelRect(
        ofCopy copyID: KittyGraphics.ImageID, column: Int, row: Int
    ) -> (x: Int, y: Int, width: Int, height: Int)? {
        derivedImages.pixelRect(ofCopy: copyID, column: column, row: row)
    }

    /// The signature of the picture `token` draws, as it was given, or `nil`
    /// if it draws none: what a view has already sent, for it to judge
    /// whether a new box needs new pixels.
    package func signature(heldBy token: String) -> Any? {
        entries[token].flatMap { images[$0]?.signature.value }
    }

    /// Keeps every picture the cells of `lines` draw — a copy's picture, for
    /// a copy's cell, which keeps the copy — until ``release(token:)``, as if
    /// `token` drew them; any it held before are let go.
    ///
    /// For a drawing that stays on screen after the views that drew it have
    /// gone: a navigation zoom's still, the screen being folded away by a
    /// pop. That screen's pictures are released as it disappears, and deleted
    /// unheld, so the zoom drew empty cells where its photo had been.
    package func hold(picturesIn lines: [String], for token: String) {
        let before = holds.removeValue(forKey: token) ?? []
        var held = Set<KittyGraphics.ImageID>()
        for line in lines where line.unicodeScalars.contains(.terminalImagePlaceholder) {
            // The ink in force, which names each picture cell's image.
            var state = SGRState()
            // `true`: on to the next segment, every time.
            _ = line.forEachANSISegment { segment in
                switch segment {
                case .visible(let character):
                    // A pattern reading the ink's channels, not a colour this
                    // draws with.
                    // swiftlint:disable:next framework_colour_literal
                    guard case .rgb(let red, let green, let blue)? = state.foregroundColour,
                        let cell = KittyGraphics.placeholderCell(
                            character,
                            foreground: (UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue)))
                    else { return true }
                    let id = derivedImages.origin(of: cell.id)?.source ?? cell.id
                    guard images[id] != nil, held.insert(id).inserted else { return true }
                    images[id]?.holders.insert(token)
                // A rendered line's escape segment, not a colour: the rule
                // matches `.ansi(` wherever it is written.
                // swiftlint:disable:next framework_colour_literal
                case .ansi(let sequence, _):
                    state.apply(sequence)
                }
                return true
            }
        }
        if !held.isEmpty { holds[token] = held }
        // After the new holds, so a picture in both is kept, not deleted and
        // sent again.
        for id in before.subtracting(held) { letGo(of: id, by: token) }
    }

    /// Gives back every image, for a shutdown that wants to leave the terminal
    /// as it found it: the deletes still owed after a frame's cells
    /// (``takeDeletes()``) with them, as there is no frame to come.
    package func releaseAll() {
        pending += farewell()
        deletes = ""
        retiring.removeAll()
        images.removeAll()
        slots.removeAll()
        entries.removeAll()
        for backdrop in backdrops { derivedImages.forget(backdrop.id) }
        backdrops.removeAll()
        _generation += 1
    }

    /// What ``releaseAll()`` would write, without releasing anything: a delete
    /// for every image, as long as the deletes fit in `limit` bytes — whole
    /// deletes only, as a cut one would leave the terminal reading the rest of
    /// its output as the command's payload.
    ///
    /// In the order the images were put in, so a shutdown writes the same
    /// bytes on every run. A dictionary's order is not that: it changes from
    /// one process to the next. The images already let go whose deletes are
    /// still owed (``takeDeletes()``) come first, in the order they went.
    ///
    /// What a `SIGQUIT` owes the terminal too, which skips the teardown that
    /// calls ``releaseAll()`` (`Terminal.quitFarewell`).
    package func farewell(fitting limit: Int = .max) -> String {
        var farewell = ""
        // Each picture's copies after it, sorted too.
        // A backdrop is never sent itself, only its copies, after the pictures,
        // in the order the backdrops were made.
        // Two statements: one expression of both took the type-check guard past
        // its limit.
        var ids: [KittyGraphics.ImageID] = images.values.sorted(by: { $0.arrival < $1.arrival }).flatMap {
            [$0.id] + derivedImages.copyIDs(of: $0.id)
        }
        for backdrop in backdrops { ids += derivedImages.copyIDs(of: backdrop.id) }
        for id in retiring + ids {
            let delete = KittyGraphics.delete(id: id)
            guard farewell.utf8.count + delete.utf8.count <= limit else { break }
            farewell += delete
        }
        return farewell
    }

    /// The escapes owed to the terminal, and clears them.
    ///
    /// Written at `beginFrame`, before the frame's cells: a placeholder naming
    /// an image the terminal has not been given yet draws nothing.
    package func takePending() -> String {
        defer { pending = "" }
        return pending
    }

    /// The deletes owed to the terminal for the images this frame let go of,
    /// and clears them.
    ///
    /// Written AFTER the frame's cells, inside its synchronized-update hold
    /// (`RenderLoop.writeFrame`): the cells that stop naming an image replace
    /// it on screen in the same held update that deletes it, so a picture
    /// swapped for another is never blank in between. A delete written with
    /// ``takePending()``, ahead of the hold, blanked the old picture for as
    /// long as the new one's bytes took to arrive.
    package func takeDeletes() -> String {
        guard !retiring.isEmpty else { return "" }
        defer {
            deletes = ""
            retiring.removeAll()
            // What a SIGQUIT owes changes with it (``farewell(fitting:)``).
            _generation += 1
        }
        return deletes
    }

    // MARK: - Filing

    /// The image of `wanted` in `slot`'s box, or `nil` if the terminal holds
    /// none.
    ///
    /// The older, if two do. Two can: a view alone on its image that asks for
    /// a new box moves the image there with a placement, and another view may
    /// already have transmitted the same picture in that box.
    private func sharedImage(of wanted: AnyImageSignature, in slot: Slot) -> KittyGraphics.ImageID? {
        var oldest: Image?
        for id in slots[slot] ?? [] {
            guard let image = images[id], image.signature == wanted else { continue }
            if let current = oldest, current.arrival < image.arrival { continue }
            oldest = image
        }
        return oldest?.id
    }

    /// Takes `token` off image `id`, and gives the image back to the terminal
    /// if nobody else is drawing it. Returns whether the image went.
    @discardableResult
    private func letGo(of id: KittyGraphics.ImageID, by token: String) -> Bool {
        guard images[id] != nil else { return false }
        images[id]?.holders.remove(token)
        guard images[id]?.holders.isEmpty == true else { return false }
        retire(id)
        deleteCopies(of: id)
        derivedImages.forget(id)
        unfile(id)
        return true
    }

    /// Deletes every copy derived from picture `id` from the terminal.
    private func deleteCopies(of id: KittyGraphics.ImageID) {
        for copy in derivedImages.copyIDs(of: id) { retire(copy) }
    }

    /// Owes the terminal a delete of image `id`, after the frame's cells
    /// (``takeDeletes()``), and keeps the id from being handed out before
    /// then.
    private func retire(_ id: KittyGraphics.ImageID) {
        deletes += KittyGraphics.delete(id: id)
        retiring.append(id)
    }

    private func file(_ image: Image) {
        images[image.id] = image
        slots[image.slot, default: []].append(image.id)
        _generation += 1
    }

    @discardableResult
    private func unfile(_ id: KittyGraphics.ImageID) -> Image? {
        guard let image = images.removeValue(forKey: id) else { return nil }
        _generation += 1
        slots[image.slot]?.removeAll { $0 == id }
        if slots[image.slot]?.isEmpty == true { slots.removeValue(forKey: image.slot) }
        return image
    }

    /// Moves image `id` to `slot`, drawn by `cells`: the same picture, placed
    /// in a new box.
    private func refile(_ id: KittyGraphics.ImageID, in slot: Slot, cells: [String]) {
        guard var image = unfile(id) else { return }
        image.slot = slot
        image.cells = cells
        file(image)
    }

    // MARK: - Ids

    /// The next id nothing is using.
    ///
    /// Counts up and wraps, skipping ids in use, ids whose deletes are still
    /// owed (``takeDeletes()``), and the two the startup
    /// handshake borrows (``TerminalGraphicsQuery/probeID`` and
    /// ``TerminalGraphicsQuery/compressionProbeID``, the top of the range).
    /// Sixteen million ids and a handful of images means the wrap is
    /// unreachable in practice; it is handled because "unreachable in
    /// practice" is how an id gets reused underneath a live picture.
    private func claimID() -> KittyGraphics.ImageID {
        for _ in 0..<KittyGraphics.maximumImageID {
            let candidate = nextID
            nextID = candidate >= KittyGraphics.maximumImageID - 2 ? 1 : candidate + 1
            if images[candidate] == nil, !derivedImages.isCopy(candidate), !isBackdrop(candidate),
                !retiring.contains(candidate)
            {
                return candidate
            }
        }
        return 1
    }
}
