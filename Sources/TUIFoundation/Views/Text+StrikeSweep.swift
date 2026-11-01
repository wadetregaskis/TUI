//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+StrikeSweep.swift
//
//  A strikethrough that changes under an animation is drawn along the text,
//  left to right, and taken back right to left, where SwiftUI cross-fades the
//  two looks: a terminal's strikethrough is an attribute of each cell, on or
//  off, with nothing between to fade through, and the owner asked for the line
//  to be drawn (2026-10-27). Under no animation it changes at once, as before.
//
//  While the strike is part-way, the text is drawn struck and the strike is
//  taken off every cell past the point the line has reached: so only cells
//  that are struck when the line is whole are ever struck, whatever else is
//  drawn beside them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// How far along its text a strikethrough is drawn: 0 none of it, 1 all.
struct StrikeSweep: Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
}

@MainActor extension Text {
    /// This text drawn by `draw`, its strikethrough part-way along it while a
    /// change to it animates.
    ///
    /// Only a text that states a strikethrough, on or off, asks the animation
    /// store: every other text pays one `nil` check.
    func sweepingStrike(context: RenderContext, draw: (Text) -> FrameBuffer) -> FrameBuffer {
        guard let stated = style.strikethrough else { return draw(self) }
        let target = StrikeSweep(progress: stated == nil ? 0 : 1)
        guard
            let drawn = animatedValue(
                of: target, owner: StrikeSweep.self, context: context, isMeasuring: context.isMeasuring)
        else { return draw(self) }
        var struck = self
        struck.style.strikethrough = .some(stated ?? .single)
        guard drawn.progress > 0 else {
            var plain = self
            plain.style.strikethrough = .some(nil)
            return draw(plain)
        }
        return draw(struck).strikingThrough(drawn.progress)
    }
}

extension FrameBuffer {
    /// This buffer with its strikethrough cleared from every cell past
    /// `progress` of its width: the line drawn that far along.
    func strikingThrough(_ progress: Double) -> FrameBuffer {
        guard progress < 1 else { return self }
        let reached = Int((progress * Double(width)).rounded())
        var swept = self
        swept.lines = lines.map { $0.clearingStrikethrough(fromCell: reached) }
        return swept
    }
}

extension String {
    /// This line with the strikethrough off from cell `column` on, whatever its
    /// own sequences say there: SGR 29 in front of the first cell at or past
    /// `column`, and again after each SGR sequence from there, any of which
    /// may restate a strike (a reset, then its style).
    func clearingStrikethrough(fromCell column: Int) -> String {
        var result = ""
        result.reserveCapacity(utf8.count + 16)
        var visible = 0
        // Whether the strike is known to be off at the output's end.
        var cleared = false
        forEachANSISegment { segment in
            switch segment {
            // Not a colour: an escape sequence of the line (`ANSISegment.ansi`).
            case .ansi(let sequence, let isSGR):  // swiftlint:disable:this framework_colour_literal
                result += sequence
                if isSGR { cleared = false }
            case .visible(let character):
                if visible >= column, !cleared {
                    result += "\u{1B}[29m"
                    cleared = true
                }
                result.append(character)
                visible += character.terminalWidth
            }
            return true
        }
        return result
    }
}

// MARK: - A subtree's strikethrough

/// ``View/strikethrough(_:pattern:color:)``: the subtree's text struck as far
/// along as the line has been drawn — at once, or under an animation along
/// its width (see the file's header).
struct _StrikethroughSweep: ViewModifier, Animatable {
    var progress: Double
    let line: Text.LineStyle

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .style(.text, StyleAttributes(strikethrough: progress > 0, strikethroughStyle: line))
            .modifier(_StrikeClip(progress: progress))
    }
}

/// Clears the strike past `progress` of the buffer's width; nothing at 0 or 1.
struct _StrikeClip: BufferModifier {
    let progress: Double

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard progress > 0 else { return buffer }
        return buffer.strikingThrough(progress)
    }
}
