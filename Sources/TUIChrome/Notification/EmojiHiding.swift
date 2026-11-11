//  🖥️ TUI — A Terminal UI framework for Swift
//  EmojiHiding.swift
//
//  A toast's emoji left blank while it fades: no fade reaches them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

extension View {
    /// This view with every emoji it draws left blank while `isHidden`: the
    /// same cells, in the same colours, with nothing in them.
    ///
    /// For a toast's fades (`NotificationToast`). An emoji is a picture in
    /// colours of its own, so a fade, which works by colour, leaves it at full
    /// strength while the text and border round it come and go. Blank, its
    /// cells fade as the rest of the toast's blank cells do, and nothing moves
    /// when it appears.
    func hidingEmoji(_ isHidden: Bool) -> some View {
        _EmojiHidingCore(content: self, isHidden: isHidden)
    }
}

/// Draws `content`, with its emoji blank while `isHidden`
/// (``View/hidingEmoji(_:)``).
///
/// Renders `content` at its own identity and context, so what the content
/// holds — its state, its buttons' focus — is the same hidden or not.
nonisolated struct _EmojiHidingCore<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let isHidden: Bool

    @MainActor var body: Never { fatalError("_EmojiHidingCore renders via Renderable") }

    @MainActor func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = TUIView.renderToBuffer(content, context: context)
        if isHidden { buffer.blankEmoji() }
        return buffer
    }

    /// Blank cells take what the emoji took, so the size is the content's.
    @MainActor func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension FrameBuffer {
    /// Each emoji in the lines, and in the layers drawn over them, made as
    /// many spaces as it is wide; every escape kept where it was, so the
    /// blanks are in the colours the emoji had.
    ///
    /// The lines and layers only: a run's frames (`animatedCells`) are left as
    /// they are, as no toast draws an emoji in one.
    mutating func blankEmoji() {
        var changed = false
        let blanked = lines.map { line in
            let blank = Self.blankingEmoji(in: line)
            if blank != nil { changed = true }
            return blank ?? line
        }
        if changed { lines = blanked }
        guard !overlays.isEmpty else { return }
        overlays = overlays.map { layer in
            var layer = layer
            layer.content.blankEmoji()
            return layer
        }
    }

    /// `line` with each emoji blank, or `nil` where it has none.
    private static func blankingEmoji(in line: String) -> String? {
        var result = ""
        var changed = false
        line.forEachANSISegment { segment in
            switch segment {
            // A segment of the line, not a colour.
            case .ansi(let sequence, _):  // swiftlint:disable:this framework_colour_literal
                result += sequence
            case .visible(let character):
                if character.drawsInItsOwnColours {
                    result += String(repeating: " ", count: character.terminalWidth)
                    changed = true
                } else {
                    result.append(character)
                }
            }
            return true
        }
        return changed ? result : nil
    }
}
