//  🖥️ TUI — A Terminal UI framework for Swift
//  SixelEncoder.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization

/// Sixel: RGBA pixels as the escape that draws them at the cursor, for a terminal
/// with no Kitty graphics (`Terminal graphics protocols.md` §6, §16).
///
/// Pure, with no terminal I/O and nothing platform-specific, so it builds wherever
/// `TUICore` does, Windows included.
///
/// No dither: an ordered one cost 37% more bytes on a photograph (§6.4), and two
/// rectangles of one picture would have to agree on its phase to show no seam.
package enum SixelEncoder {

    /// What a pixel is flattened over, there being no alpha in Sixel: the colour
    /// behind the picture where it is known. Where it is not, a pixel more than half
    /// transparent is left unset and any other is opaque, which is all the alpha the
    /// protocol has (`P2=1`).
    package typealias Background = (red: UInt8, green: UInt8, blue: UInt8)

    /// A picture's colours, shared by every rectangle of it, so two of them meeting
    /// show no seam.
    package struct Palette: Sendable {
        /// The colours, each three bytes.
        fileprivate var colours: [UInt8] = []
        /// The nearest colour by a pixel's top five bits a channel, found as asked
        /// for: `Palette.unknown` until then.
        fileprivate var nearest: [UInt16]

        fileprivate static let unknown = UInt16.max
        fileprivate static let transparent = UInt16.max - 1

        /// How many colours it holds.
        package var count: Int { colours.count / 3 }

        /// At most `limit` colours for `rgba`, by median cut over a 32 x 32 x 32 grid.
        ///
        /// Its own and not `ASCIIPalette.adaptive`'s, which is in `TUIImage` and takes
        /// the render path's question (OKLab, a lattice, a depth), out of reach of the
        /// module this is in.
        package init(rgba: [UInt8], background: Background?, limit: Int = 256) {
            nearest = [UInt16](repeating: Self.unknown, count: 1 << 15)
            // Each cell of the grid's pixels and the sum of their channels, so that a
            // box's colour is what its pixels average to: white stays white.
            var counts = [UInt32](repeating: 0, count: 1 << 15)
            var sums = [UInt64](repeating: 0, count: 3 << 15)
            Self.forEachPixel(rgba, background: background) { red, green, blue in
                let key = Self.key(red, green, blue)
                counts[key] += 1
                sums[key * 3] += UInt64(red)
                sums[key * 3 + 1] += UInt64(green)
                sums[key * 3 + 2] += UInt64(blue)
            }
            var occupied: [Bucket] = []
            for (key, count) in counts.enumerated() where count > 0 {
                occupied.append(Bucket(key: key, count: count, red: sums[key * 3], green: sums[key * 3 + 1], blue: sums[key * 3 + 2]))
            }
            colours = Self.medianCut(occupied, into: max(1, min(limit, 256)))
        }

        /// One cell of the grid: its pixels, and the sums of their channels.
        private struct Bucket {
            var key: Int
            var count: UInt32
            var red: UInt64
            var green: UInt64
            var blue: UInt64
        }

        /// Calls `body` with each pixel flattened, skipping one left unset.
        fileprivate static func forEachPixel(
            _ rgba: [UInt8], background: Background?, _ body: (UInt8, UInt8, UInt8) -> Void
        ) {
            rgba.withUnsafeBufferPointer { bytes in
                var offset = 0
                while offset + 3 < bytes.count {
                    if let pixel = unsafe flattened(bytes, at: offset, over: background) { body(pixel.0, pixel.1, pixel.2) }
                    offset += 4
                }
            }
        }

        @inline(__always)
        fileprivate static func key(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Int {
            // Apart, or the solver gives up on one expression of shifts and ors.
            let high: Int = Int(red >> 3) << 10
            let middle: Int = Int(green >> 3) << 5
            return high | middle | Int(blue >> 3)
        }

        /// Splits the box with the widest channel at its middle pixel, until there are
        /// `count` boxes or no box holds two colours; a box's colour is its average.
        private static func medianCut(_ occupied: [Bucket], into count: Int) -> [UInt8] {
            guard !occupied.isEmpty else { return [0, 0, 0] }
            var boxes = [occupied]
            func channel(_ key: Int, _ shift: Int) -> Int { (key >> shift) & 31 }
            func widest(_ box: [Bucket]) -> (shift: Int, range: Int) {
                var best = (shift: 0, range: -1)
                for shift in [10, 5, 0] {
                    var low = 31
                    var high = 0
                    for entry in box {
                        let value = channel(entry.key, shift)
                        low = min(low, value)
                        high = max(high, value)
                    }
                    if high - low > best.range { best = (shift, high - low) }
                }
                return best
            }
            while boxes.count < count {
                var chosen = -1
                var chosenRange = 0
                for (index, box) in boxes.enumerated() where box.count > 1 {
                    let range = widest(box).range
                    if range > chosenRange {
                        chosen = index
                        chosenRange = range
                    }
                }
                guard chosen >= 0 else { break }
                let shift = widest(boxes[chosen]).shift
                let sorted = boxes[chosen].sorted { channel($0.key, shift) < channel($1.key, shift) }
                let half = sorted.reduce(UInt64(0)) { $0 + UInt64($1.count) } / 2
                var seen = UInt64(0)
                var split = 1
                for (index, entry) in sorted.enumerated() {
                    seen += UInt64(entry.count)
                    if seen >= half {
                        split = max(1, min(index + 1, sorted.count - 1))
                        break
                    }
                }
                boxes[chosen] = Array(sorted[..<split])
                boxes.append(Array(sorted[split...]))
            }
            var colours: [UInt8] = []
            colours.reserveCapacity(boxes.count * 3)
            for box in boxes {
                var total = UInt64(0)
                var sums = (UInt64(0), UInt64(0), UInt64(0))
                for entry in box {
                    total += UInt64(entry.count)
                    sums.0 += entry.red
                    sums.1 += entry.green
                    sums.2 += entry.blue
                }
                colours += [UInt8(sums.0 / total), UInt8(sums.1 / total), UInt8(sums.2 / total)]
            }
            return colours
        }

        /// The register for a pixel of this colour.
        fileprivate mutating func register(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> UInt16 {
            let key = Self.key(red, green, blue)
            let known = nearest[key]
            if known != Self.unknown { return known }
            let red = Int(red)
            let green = Int(green)
            let blue = Int(blue)
            var best = 0
            var bestDistance = Int.max
            var index = 0
            while index < count {
                let deltaRed = Int(colours[index * 3]) - red
                let deltaGreen = Int(colours[index * 3 + 1]) - green
                let deltaBlue = Int(colours[index * 3 + 2]) - blue
                let distance = deltaRed * deltaRed + deltaGreen * deltaGreen + deltaBlue * deltaBlue
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
                index += 1
            }
            nearest[key] = UInt16(best)
            return UInt16(best)
        }
    }

    /// The pixel at `offset` flattened over `background`, or `nil` for one left
    /// unset: see ``Background``.
    @inline(__always)
    fileprivate static func flattened(
        _ bytes: UnsafeBufferPointer<UInt8>, at offset: Int, over background: Background?
    ) -> (UInt8, UInt8, UInt8)? {
        let alpha = unsafe Int(bytes[offset + 3])
        if alpha == 255 { return unsafe (bytes[offset], bytes[offset + 1], bytes[offset + 2]) }
        guard let background else {
            return unsafe alpha < 128 ? nil : (bytes[offset], bytes[offset + 1], bytes[offset + 2])
        }
        func mix(_ over: UInt8, _ under: UInt8) -> UInt8 {
            UInt8((Int(over) * alpha + Int(under) * (255 - alpha) + 127) / 255)
        }
        return unsafe (
            mix(bytes[offset], background.red), mix(bytes[offset + 1], background.green),
            mix(bytes[offset + 2], background.blue)
        )
    }

    // MARK: - Encoding

    /// The escape that draws `rgba`, `width` x `height` pixels, at the cursor.
    ///
    /// `P2=1` so an unset pixel leaves what is there, with raster attributes so a
    /// height not a multiple of six is still that height: its last band's lower bits
    /// are unset, and the row below keeps its text (measured, `sixel_probe.py`, I).
    package static func encode(
        rgba: [UInt8], width: Int, height: Int, palette: inout Palette, background: Background?
    ) -> String {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return "" }
        var registers = [UInt16](repeating: Palette.transparent, count: width * height)
        var used = [Bool](repeating: false, count: palette.count)
        rgba.withUnsafeBufferPointer { bytes in
            for index in 0..<(width * height) {
                guard let pixel = unsafe flattened(bytes, at: index * 4, over: background) else { continue }
                let register = palette.register(pixel.0, pixel.1, pixel.2)
                registers[index] = register
                used[Int(register)] = true
            }
        }
        var out: [UInt8] = []
        out.reserveCapacity(width * height)
        appendASCII("\u{1B}P0;1;0q\"1;1;\(width);\(height)", to: &out)
        for register in 0..<palette.count where used[register] {
            func percent(_ offset: Int) -> Int { (Int(palette.colours[register * 3 + offset]) * 100 + 127) / 255 }
            appendASCII("#\(register);2;\(percent(0));\(percent(1));\(percent(2))", to: &out)
        }
        appendBands(of: registers, width: width, height: height, colours: palette.count, to: &out)
        appendASCII("\u{1B}\\", to: &out)
        // swiftlint:disable:next optional_data_string_conversion - no `Data`; ASCII this just wrote
        return String(decoding: out, as: UTF8.self)
    }

    private static func appendASCII(_ text: String, to out: inout [UInt8]) {
        out.append(contentsOf: text.utf8)
    }

    /// Each band of six pixel rows: for each colour in it, a pass from the left edge
    /// to that colour's last pixel, in `!n` runs.
    private static func appendBands(
        of registers: [UInt16], width: Int, height: Int, colours: Int, to out: inout [UInt8]
    ) {
        var bits = [UInt8](repeating: 0, count: colours * width)
        var lastColumn = [Int](repeating: -1, count: colours)
        var touched: [Int] = []
        var top = 0
        while top < height {
            touched.removeAll(keepingCapacity: true)
            for offset in 0..<min(6, height - top) {
                let start = (top + offset) * width
                for column in 0..<width {
                    let register = Int(registers[start + column])
                    guard register < colours else { continue }
                    if lastColumn[register] < 0 { touched.append(register) }
                    bits[register * width + column] |= UInt8(1) << UInt8(offset)
                    lastColumn[register] = max(lastColumn[register], column)
                }
            }
            touched.sort()
            for (position, register) in touched.enumerated() {
                if position > 0 { out.append(UInt8(ascii: "$")) }
                appendASCII("#\(register)", to: &out)
                let start = register * width
                appendRuns(bits[start...(start + lastColumn[register])], to: &out)
                for column in 0...lastColumn[register] { bits[start + column] = 0 }
                lastColumn[register] = -1
            }
            out.append(UInt8(ascii: "-"))
            top += 6
        }
    }

    /// `values` as sixel characters: `!n` for four or more alike, where it is shorter.
    private static func appendRuns(_ values: ArraySlice<UInt8>, to out: inout [UInt8]) {
        var index = values.startIndex
        while index < values.endIndex {
            let value = values[index]
            var end = index + 1
            while end < values.endIndex, values[end] == value { end += 1 }
            let run = end - index
            let character = value + 63
            if run > 3 {
                appendASCII("!\(run)", to: &out)
                out.append(character)
            } else {
                for _ in 0..<run { out.append(character) }
            }
            index = end
        }
    }

    // MARK: - Fitting pixels to cells

    /// `rgba` at `toWidth` x `toHeight`: each new pixel the average of the old ones it
    /// covers, or the nearest where it covers fewer than one. There is no `c`,`r` in
    /// Sixel to have the terminal fit a picture to its cells.
    package static func resampled(
        rgba: [UInt8], width: Int, height: Int, toWidth: Int, toHeight: Int
    ) -> [UInt8] {
        guard toWidth > 0, toHeight > 0, width > 0, height > 0, rgba.count >= width * height * 4 else { return [] }
        if width == toWidth, height == toHeight { return rgba }
        return unsafe [UInt8](unsafeUninitializedCapacity: toWidth * toHeight * 4) { out, count in
            rgba.withUnsafeBufferPointer { bytes in
                var written = 0
                for y in 0..<toHeight {
                    let top = y * height / toHeight
                    let bottom = max(top + 1, (y + 1) * height / toHeight)
                    for x in 0..<toWidth {
                        let left = x * width / toWidth
                        let right = max(left + 1, (x + 1) * width / toWidth)
                        let total = unsafe averaged(bytes, width: width, left: left, right: right, top: top, bottom: bottom)
                        unsafe out[written] = total.0
                        unsafe out[written + 1] = total.1
                        unsafe out[written + 2] = total.2
                        unsafe out[written + 3] = total.3
                        written += 4
                    }
                }
            }
            count = toWidth * toHeight * 4
        }
    }

    /// The average of a rectangle of pixels: straight, as the pixels are not
    /// premultiplied and a transparent pixel's colour counts for nothing in a
    /// flattened one only by its alpha, which this averages too.
    @inline(__always)
    private static func averaged(
        _ bytes: UnsafeBufferPointer<UInt8>, width: Int, left: Int, right: Int, top: Int, bottom: Int
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        if right - left == 1, bottom - top == 1 {
            let offset = (top * width + left) * 4
            return unsafe (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
        }
        var sums = (0, 0, 0, 0)
        for row in top..<bottom {
            var offset = (row * width + left) * 4
            for _ in left..<right {
                unsafe sums.0 += Int(bytes[offset])
                unsafe sums.1 += Int(bytes[offset + 1])
                unsafe sums.2 += Int(bytes[offset + 2])
                unsafe sums.3 += Int(bytes[offset + 3])
                offset += 4
            }
        }
        let count = (right - left) * (bottom - top)
        return (UInt8(sums.0 / count), UInt8(sums.1 / count), UInt8(sums.2 / count), UInt8(sums.3 / count))
    }

    // MARK: - The glyphs for a picture its pixels have to wait for

    /// `rgba` as half blocks, one string a cell, for a block over the frame's byte
    /// bound: about 40 bytes a cell against about 400 to 950 of pixels (§6.4). Each
    /// states its colours; the caller resets after the last it writes.
    package static func halfBlocks(
        rgba: [UInt8], width: Int, height: Int, columns: Int, rows: Int, background: Background?
    ) -> [[String]] {
        let cells = resampled(rgba: rgba, width: width, height: height, toWidth: columns, toHeight: rows * 2)
        guard !cells.isEmpty else { return [] }
        let under: Background = background ?? (0, 0, 0)
        return cells.withUnsafeBufferPointer { bytes in
            func colour(_ offset: Int) -> (UInt8, UInt8, UInt8) {
                unsafe flattened(bytes, at: offset, over: under) ?? (under.red, under.green, under.blue)
            }
            return (0..<rows).map { row in
                (0..<columns).map { column in
                    let upper = colour((row * 2 * columns + column) * 4)
                    let lower = colour(((row * 2 + 1) * columns + column) * 4)
                    return "\u{1B}[38;2;\(upper.0);\(upper.1);\(upper.2);48;2;\(lower.0);\(lower.1);\(lower.2)m\u{2580}"
                }
            }
        }
    }
}

// MARK: - Whether this terminal draws pictures by Sixel

extension KittyGraphics {

    /// Whether the picture cells are drawn by Sixel: published from
    /// `TerminalClient.applyGraphicsSupport()`. Nothing above the writer knows:
    /// `_ImageCore` and the store go on making placeholder cells, as they do for a
    /// host drawing by classic placements, which this is on top of
    /// (``drawsPicturesByClassicPlacement`` is `true` too).
    ///
    /// The difference at the wire: no APC at all. ``transmit(pixels:format:width:height:id:compressed:)``
    /// is not asked, as the store keeps the pixels instead, and ``delete(id:)``
    /// answers `""`. **Defaults to `false`.**
    package static var drawsPicturesBySixel: Bool {
        get { taskSixel ?? processSixel.load(ordering: .relaxed) }
        set { processSixel.store(newValue, ordering: .relaxed) }
    }

    /// Atomic for the reason ``isSupported`` gives.
    private static let processSixel = Atomic(false)

    /// A task-scoped pin, bound by ``withSixel(_:operation:)``.
    @TaskLocal private static var taskSixel: Bool?

    /// Runs `operation` with ``drawsPicturesBySixel`` pinned on this task only:
    /// tests run in parallel.
    @discardableResult
    package static func withSixel<T>(_ drawn: Bool, operation: () throws -> T) rethrows -> T {
        try $taskSixel.withValue(drawn, operation: operation)
    }

    /// `content` with each run of the bare placeholder a move past those cells. What
    /// the writer sends on a Sixel host for a picture's cells: they keep their place
    /// in the row's width, and are not written, as a written cell erases the pixels
    /// in it (measured, `sixel_probe.py`, B).
    ///
    /// A whole row built for this opens with `ESC[2K`, which would take its pixels
    /// away (measured, D), so it goes too if there is a picture cell in it: a built row
    /// is padded to its full width, so its erase is writing nothing else needs.
    package static func skippingPictureCells(_ content: String) -> String {
        var content = content
        return content.withUTF8 { bytes -> String in
            // U+10EEEE in UTF-8, and `ESC[2K`.
            let marker: [UInt8] = [0xF4, 0x8E, 0xBB, 0xAE]
            let erase: [UInt8] = [0x1B, 0x5B, 0x32, 0x4B]
            func matches(_ pattern: [UInt8], at index: Int) -> Bool {
                guard index + pattern.count <= bytes.count else { return false }
                for offset in 0..<pattern.count where unsafe bytes[index + offset] != pattern[offset] { return false }
                return true
            }
            var out: [UInt8] = []
            out.reserveCapacity(bytes.count)
            var index = 0
            var sawCell = false
            var eraseAt: Int?
            while index < bytes.count {
                var cells = 0
                while matches(marker, at: index) {
                    cells += 1
                    index += marker.count
                }
                if cells > 0 {
                    sawCell = true
                    out.append(contentsOf: "\u{1B}[\(cells)C".utf8)
                } else if eraseAt == nil, !sawCell, matches(erase, at: index) {
                    eraseAt = out.count
                    out.append(contentsOf: erase)
                    index += erase.count
                } else {
                    unsafe out.append(bytes[index])
                    index += 1
                }
            }
            if sawCell, let eraseAt { out.removeSubrange(eraseAt..<(eraseAt + erase.count)) }
            // swiftlint:disable:next optional_data_string_conversion - no `Data`; whole scalars of valid UTF-8
            return String(decoding: out, as: UTF8.self)
        }
    }
}
