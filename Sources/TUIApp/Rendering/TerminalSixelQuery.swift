//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalSixelQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#endif

// MARK: - What the terminal says about its Sixel

extension Terminal {
    /// Asks DA1 alone, for a host about to be asked whether it speaks Sixel.
    func queryPrimaryAttributes(timeout: Double = 0.5) -> String? {
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return nil }
        let collected = fencedExchange(
            request: "\u{1B}[c" + TerminalQueryReplies.statusFence, timeout: timeout,
            sawFence: { TerminalIdentityQuery.parse($0).sawFence })
        let identity = TerminalIdentityQuery.parse(collected)
        if !identity.unconsumed.isEmpty { enqueue(input: identity.unconsumed) }
        return identity.primaryAttributes
    }

    /// Asks how many colour registers the terminal has, and how big a cell is, for a
    /// host about to draw by Sixel. One exchange, fenced as the others are.
    func querySixelGeometry(timeout: Double = 0.5) -> (registers: Int?, cell: TerminalCellPixels?) {
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return (nil, nil) }
        let collected = fencedExchange(
            request: SixelGeometryQuery.request, timeout: timeout, sawFence: TerminalQueryReplies.sawStatusFence)
        handBackUnconsumed(
            from: collected, isReply: SixelGeometryQuery.isReply, isFence: TerminalQueryReplies.isStatusFence)
        return SixelGeometryQuery.parse(collected)
    }
}

/// The questions for a host about to draw by Sixel, and their answers.
enum SixelGeometryQuery {
    /// `XTSMGRAPHICS`, the registers, read; the cell in pixels; the fence.
    static let request = "\u{1B}[?1;1;0S\u{1B}[16t\u{1B}[5n"

    /// Whether `sequence` is one of the replies: `CSI ? 1 ; … S` or `CSI 6 ; … t`.
    static func isReply(_ sequence: ArraySlice<UInt8>) -> Bool {
        let text = Array(sequence)
        guard text.count > 3, text[0] == 0x1B, text[1] == 0x5B else { return false }
        return (text[2] == 0x3F && text.last == 0x53) || (text[2] == 0x36 && text.last == 0x74)
    }

    /// The numbers in `bytes`: a register count clamped to what a palette can use, and
    /// a cell, where they came.
    static func parse(_ bytes: [UInt8]) -> (registers: Int?, cell: TerminalCellPixels?) {
        // swiftlint:disable:next optional_data_string_conversion - no `Data`; a reply is ASCII or it matches nothing
        let text = String(decoding: bytes, as: UTF8.self)
        var registers: Int?
        var cell: TerminalCellPixels?
        for part in text.split(separator: "\u{1B}") {
            guard part.hasPrefix("[") else { continue }
            let body = part.dropFirst()
            if body.hasPrefix("?1;"), body.hasSuffix("S") {
                let fields = body.dropFirst(3).dropLast().split(separator: ";")
                // `?1;0;N`: status zero is success.
                if fields.count == 2, fields[0] == "0", let count = Int(fields[1]) {
                    registers = max(2, min(count, 256))
                }
            } else if body.hasPrefix("6;"), body.hasSuffix("t") {
                let fields = body.dropFirst(2).dropLast().split(separator: ";")
                if fields.count == 2, let height = Int(fields[0]), let width = Int(fields[1]), width > 0, height > 0 {
                    cell = TerminalCellPixels(width: width, height: height)
                }
            }
        }
        return (registers, cell)
    }
}
