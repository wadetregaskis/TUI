//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScreenSelection+RichText.swift
//
//  A screen selection with its styling, as HTML: the colours, weight and
//  decoration the cells were drawn with, for a copy to carry beside its text
//  where the terminal takes more than text (OSC 5522).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

extension ScreenSelection {
    /// The forms a copy of the selection carries beside its text: its cells'
    /// styling as `text/html`. None for an empty selection.
    func representations() -> [ClipboardRepresentation] {
        guard let selection = current, !selection.text.isEmpty else { return [] }
        return [ClipboardRepresentation(type: "text/html", text: Self.html(of: selection, in: frameLines))]
    }

    /// A line taken apart into cells as ``cells(of:)`` does, each with the
    /// styling it was drawn in.
    static func styledCells(of line: String) -> [(character: Character?, style: SGRState)] {
        var cells: [(character: Character?, style: SGRState)] = []
        var style = SGRState()
        line.forEachANSISegment { segment in
            switch segment {
            // An escape sequence's case, not a colour.
            case .ansi(let sequence, let isSGR):  // swiftlint:disable:this framework_colour_literal
                if isSGR { style.apply(sequence) }
            case .visible(let character):
                let width = character.terminalWidth
                guard width > 0 else { return true }
                let isPicture = character.unicodeScalars.first == Unicode.Scalar.terminalImagePlaceholder
                cells.append((isPicture ? " " : character, style))
                for _ in 1..<width { cells.append((nil, style)) }
            }
            return true
        }
        return cells
    }

    /// The selection as HTML: a `<pre>` of its rows, as ``text(of:in:)``
    /// reads them, each run of cells drawn alike one `<span>` stating its
    /// colours, weight and decoration. The terminal's default colours are
    /// left unstated, so a paste takes the destination's.
    package static func html(of selection: Selection, in lines: [String]) -> String {
        var cache: [Int: [(character: Character?, style: SGRState)]] = [:]
        func styled(_ row: Int) -> [(character: Character?, style: SGRState)] {
            if let cached = cache[row] { return cached }
            let cells = row >= 0 && row < lines.count ? styledCells(of: lines[row]) : []
            cache[row] = cells
            return cells
        }
        let (start, end) = ends(of: selection) { row in styled(row).map(\.character) }
        var rows: [String] = []
        for row in start.y...max(start.y, end.y) {
            var resolved = selection
            (resolved.anchor, resolved.head) = (start, end)
            resolved.unit = .character
            let cells = styled(row)
            guard let columns = columns(of: resolved, onRow: row, cells: cells.map(\.character)) else { continue }
            var taken = columns.filter { $0 < cells.count }.compactMap { column in
                cells[column].character.map { (character: $0, style: cells[column].style) }
            }
            // Trailing blanks dropped, as the text drops them.
            while taken.last?.character == " " { taken.removeLast() }
            rows.append(htmlRow(taken))
        }
        return "<pre style=\"font-family: ui-monospace, Menlo, monospace\">" + rows.joined(separator: "\n") + "</pre>"
    }

    /// One row's cells as runs of `<span>`s, plain text where a run is drawn
    /// in the terminal's defaults.
    private static func htmlRow(_ cells: [(character: Character, style: SGRState)]) -> String {
        var out = ""
        var index = 0
        while index < cells.count {
            let style = cells[index].style
            var run = ""
            while index < cells.count, cells[index].style == style {
                run += escaped(cells[index].character)
                index += 1
            }
            let css = self.css(style)
            out += css.isEmpty ? run : "<span style=\"\(css)\">\(run)</span>"
        }
        return out
    }

    /// `style` as CSS declarations; empty for the terminal's defaults.
    private static func css(_ style: SGRState) -> String {
        var foreground = style.foregroundColour.flatMap { hex($0, background: false) }
        var background = style.backgroundColour.flatMap { hex($0, background: true) }
        if style.isOn(7) {
            // Reversed: the pair exchanged, a default side spelled as the
            // page's own colours, which CSS names.
            (foreground, background) = (background ?? "Canvas", foreground ?? "CanvasText")
        }
        var declarations: [String] = []
        if let foreground { declarations.append("color: \(foreground)") }
        if let background { declarations.append("background-color: \(background)") }
        if style.isOn(1) { declarations.append("font-weight: bold") }
        if style.isOn(2) { declarations.append("opacity: 0.6") }
        if style.isOn(3) { declarations.append("font-style: italic") }
        let lines = [style.isOn(4) ? "underline" : nil, style.isOn(9) ? "line-through" : nil].compactMap { $0 }
        if !lines.isEmpty { declarations.append("text-decoration: " + lines.joined(separator: " ")) }
        return declarations.joined(separator: "; ")
    }

    /// An SGR colour as `#rrggbb`: a named or low indexed one as the terminal
    /// reports its slot, or xterm's where it has not (``Color/rgbComponents``),
    /// the cube and the grey ramp by their formula.
    private static func hex(_ colour: SGRState.Colour, background: Bool) -> String? {
        let rgb: (red: UInt8, green: UInt8, blue: UInt8)?
        // Reading the colours the cells were drawn in, for a copy: arithmetic on
        // content, not ink a control draws with.
        // swiftlint:disable framework_colour_literal
        switch colour {
        case .named(let code):
            let base = background ? 40 : 30
            let slot: Int? =
                (base...(base + 7)).contains(code) ? code - base
                : ((base + 60)...(base + 67)).contains(code) ? code - base - 52 : nil
            rgb = slot.flatMap { ANSIColor(rawValue: UInt8($0)) }.flatMap { Color.ansi($0).rgbComponents }
        case .indexed(let index) where (0...15).contains(index):
            rgb = ANSIColor(rawValue: UInt8(index)).flatMap { Color.ansi($0).rgbComponents }
        case .indexed(let index):
            rgb = (16...255).contains(index) ? Color.palette256ToRGB(UInt8(index)) : nil
        case .rgb(let red, let green, let blue):
            rgb = (UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue))
        }
        // swiftlint:enable framework_colour_literal
        return rgb.map { String(format: "#%02x%02x%02x", $0.red, $0.green, $0.blue) }
    }

    /// `character` safe inside HTML text.
    private static func escaped(_ character: Character) -> String {
        switch character {
        case "<": "&lt;"
        case ">": "&gt;"
        case "&": "&amp;"
        default: String(character)
        }
    }
}
