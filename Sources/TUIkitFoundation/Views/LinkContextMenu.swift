//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinkContextMenu.swift
//
//  The menu a right-click or Shift+F10 opens on a link: Show Link, then the
//  ways to copy it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - The label's words

/// The words a link's label drew last, for Copy Label and Copy as Markdown.
///
/// Read from what was drawn rather than from the label, because a label is
/// any view — a `Text`, a `Label` with an icon, a stack — and what it says is
/// what is on screen. Kept in the link's `@State` and written as the label
/// draws, so a menu chosen frames later copies the words then shown.
@MainActor
final class LinkLabelText {
    /// The label's words, one space between rows; empty until it draws.
    var text = ""
}

/// Writes the words a label drew into a ``LinkLabelText`` — the cells, without
/// their colours or a private-use glyph, trimmed, a label of several rows
/// joined by spaces.
///
/// A private-use glyph is an SF Symbol drawn in a font that has it — a
/// `Label`'s icon, `􀫊 apple/swift` — and pasted anywhere else it is a box,
/// so Copy Label copies `apple/swift`.
struct RecordsLinkLabelText: BufferModifier {
    let record: LinkLabelText

    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        if !context.isMeasuring {
            record.text = buffer.lines
                .map { line in
                    String(String.UnicodeScalarView(line.stripped.unicodeScalars.filter { !Self.isPrivateUse($0) }))
                        .trimmingCharacters(in: .whitespaces)
                }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return buffer
    }

    /// Whether `scalar` is in a private use area: U+E000–U+F8FF, or planes
    /// 15 and 16, where SF Symbols are.
    static func isPrivateUse(_ scalar: Unicode.Scalar) -> Bool {
        (0xE000...0xF8FF).contains(scalar.value) || scalar.value >= 0xF0000
    }
}

// MARK: - The menu

/// A link's context menu.
///
/// Show Link raises the popover that shows the destination, where the link
/// is a control; a link that writes its URL on the row has none. "Open" is
/// kept for opening the destination in the browser of the machine the
/// terminal is on, which nothing yet can. Copy Link copies the
/// destination; Copy Label the words the link shows, offered only where they
/// are not the destination written out (``LinkContextMenu/labelIsDestination(_:_:)``);
/// Copy as Markdown both, as `[label](destination)`, or as an autolink,
/// `<destination>`, where the label is the destination. Each copy is announced
/// in the status bar, since nothing else on screen changes.
///
/// TUI-specific: SwiftUI's `Link` has no menu of its own — a Mac's text view
/// offers Copy Link on a link in it.
struct LinkContextMenu: View {
    let destination: URL
    /// The words the label drew, or `nil` where it draws none of its own.
    let label: LinkLabelText?
    let clipboard: ClipboardAccess
    /// Raises the destination's popover, or `nil` where there is none.
    let show: (() -> Void)?

    var body: some View {
        let url = destination.absoluteString
        let words = label?.text ?? ""
        if let show {
            Button(LocalizationService.shared.string(for: LocalizationKey.Menu.showLink), action: show)
            Divider()
        }
        Button(LocalizationService.shared.string(for: LocalizationKey.Menu.copyLink)) {
            _ = clipboard.write(url, announcingSuccess: true)
        }
        if !words.isEmpty, !Self.labelIsDestination(words, destination) {
            Button(LocalizationService.shared.string(for: LocalizationKey.Menu.copyLinkLabel)) {
                _ = clipboard.write(words, announcingSuccess: true)
            }
        }
        Button(LocalizationService.shared.string(for: LocalizationKey.Menu.copyLinkAsMarkdown)) {
            _ = clipboard.write(Self.markdown(label: words, destination: destination), announcingSuccess: true)
        }
    }

    /// Whether `label` is `destination` written out — as it is, or without
    /// its scheme, a leading `www.` or a trailing `/`, the ways a link's words
    /// commonly shorten its address (`swift.org` for `https://swift.org/`).
    static func labelIsDestination(_ label: String, _ destination: URL) -> Bool {
        func bare(_ text: String) -> String {
            var text = Substring(text.lowercased())
            if let scheme = text.range(of: "://") { text = text[scheme.upperBound...] }
            if text.hasPrefix("www.") { text = text.dropFirst(4) }
            while text.hasSuffix("/") { text = text.dropLast() }
            return String(text)
        }
        return bare(label) == bare(destination.absoluteString)
    }

    /// The link as Markdown: `[label](destination)`, the label's brackets and
    /// backslashes escaped and the destination's parentheses percent-encoded so
    /// that neither ends its part early; `<destination>` where the label is the
    /// destination, or there is none.
    static func markdown(label: String, destination: URL) -> String {
        let url = destination.absoluteString
        guard !label.isEmpty, !labelIsDestination(label, destination) else { return "<\(url)>" }
        var escaped = ""
        for character in label {
            if character == "[" || character == "]" || character == "\\" { escaped.append("\\") }
            escaped.append(character)
        }
        let target = url.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        return "[\(escaped)](\(target))"
    }
}
