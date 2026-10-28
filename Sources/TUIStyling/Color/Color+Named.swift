//  🖥️ TUI — A Terminal UI framework for Swift
//  Color+Named.swift
//
//  A colour from the word that names it in Swift source: what an inline
//  Markdown attribute such as `^[x](foregroundColor: red)` spells.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Color {
    /// The colour `name` spells, or `nil` for a name TUI has no colour by.
    ///
    /// A name is spelled as the Swift source spells the colour, so the words
    /// a reader already knows mean what they mean there:
    ///
    /// - a static colour — `red`, `blue`, `magenta`, `gray`, `black`,
    ///   `white`, `default` and the rest of Apple's system names;
    /// - a semantic one — `primary`, `secondary`, `accentColor`, `warning`,
    ///   `error`, `success` — and any palette role, bare or as
    ///   `palette.accent`, `palette.foregroundTertiary`; these resolve
    ///   against the palette when drawn, as `Color.palette.accent` does;
    /// - `#rgb` or `#rrggbb`, as ``hex(_:)-(String)`` reads it. The `#` is
    ///   required, so that a word such as `bad` is never read as hex.
    ///
    /// `clear` is not among them: a colour that draws nothing has no use in
    /// a run of text.
    package static func named(_ name: String) -> Color? {
        if name.hasPrefix("#") { return hex(name) }
        if let named = staticNames[name] { return named }
        let role = name.hasPrefix("palette.") ? String(name.dropFirst("palette.".count)) : name
        return SemanticColor(rawValue: role).map { Color(value: .semantic($0)) }
    }

    /// `Color`'s own static colours, by their Swift names: a constant table,
    /// read only.
    private static let staticNames: [String: Color] = [
        "black": .black, "white": .white, "red": .red, "yellow": .yellow, "green": .green, "cyan": .cyan,
        "blue": .blue, "magenta": .magenta, "gray": .gray, "orange": .orange, "pink": .pink, "purple": .purple,
        "brown": .brown, "mint": .mint, "teal": .teal, "indigo": .indigo, "default": .default,
        "primary": .primary, "secondary": .secondary, "accentColor": .accentColor, "warning": .warning,
        "error": .error, "success": .success,
    ]
}
