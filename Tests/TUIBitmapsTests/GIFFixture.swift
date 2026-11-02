//  🖥️ TUI — A Terminal UI framework for Swift
//  GIFFixture.swift
//
//  GIF files written byte by byte for the animated picture's tests: a file whose
//  every block the test states, with no checked-in binary.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A GIF of solid rectangles, in a palette of grey levels.
struct GIFFixture {
    struct Frame {
        /// Which grey, 0 to 127 (a palette entry, the level being twice that).
        var grey: UInt8
        /// Its rectangle, or `nil` for the whole picture.
        var rect: (x: Int, y: Int, width: Int, height: Int)?
        /// Its delay, in hundredths of a second.
        var delay = 10
        /// What happens to it after it shows: 1 leaves it, 2 clears it, 3 restores
        /// what was under it.
        var disposal: UInt8 = 1
    }

    var width = 8
    var height = 8
    var frames: [Frame]
    /// The looping extension's count of repeats, or `nil` for no extension.
    var repeats: Int?

    /// The level of grey `index` in the palette.
    static func level(_ index: UInt8) -> UInt8 { index * 2 }

    var data: Data {
        var bytes = Array("GIF89a".utf8)
        func little(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
        bytes += little(width) + little(height)
        // A global table of 128 colours, so codes of 7 bits and pixels of a byte.
        bytes += [0xF6, 0, 0]
        for index in 0..<128 { bytes += [UInt8(index * 2), UInt8(index * 2), UInt8(index * 2)] }
        if let repeats {
            bytes += [0x21, 0xFF, 11]
            bytes += Array("NETSCAPE2.0".utf8)
            bytes += [3, 1]
            bytes += little(repeats)
            bytes.append(0)
        }
        for frame in frames {
            bytes += [0x21, 0xF9, 4, frame.disposal << 2]
            bytes += little(frame.delay)
            bytes += [0, 0]
            let rect = frame.rect ?? (0, 0, width, height)
            bytes.append(0x2C)
            for field in [rect.x, rect.y, rect.width, rect.height] { bytes += little(field) }
            bytes += [0, 7]
            bytes += Self.subBlocks(Self.codes(grey: frame.grey, count: rect.width * rect.height))
            bytes.append(0)
        }
        return Data(bytes + [0x3B])
    }

    /// LZW with nothing compressed: a clear code often enough that codes stay
    /// eight bits, each pixel its own code, and the end.
    private static func codes(grey: UInt8, count: Int) -> [UInt8] {
        var codes: [UInt8] = []
        for pixel in 0..<count {
            if pixel.isMultiple(of: 100) { codes.append(128) }
            codes.append(grey)
        }
        return codes + [129]
    }

    private static func subBlocks(_ bytes: [UInt8]) -> [UInt8] {
        stride(from: 0, to: bytes.count, by: 255).flatMap { start -> [UInt8] in
            let block = bytes[start..<min(start + 255, bytes.count)]
            return [UInt8(block.count)] + block
        }
    }

    /// Writes the file somewhere only this test looks, returning its path.
    func write() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-fixture-\(UUID().uuidString).gif").path
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}
