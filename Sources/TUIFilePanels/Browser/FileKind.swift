//  🖥️ TUI — A Terminal UI framework for Swift
//  FileKind.swift
//
//  The kinds of item a file panel draws an icon for: a folder and a handful of
//  common kinds of file, each with the glyph it is drawn with where the
//  terminal draws glyphs of that repertoire.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// What kind of item a file panel's row is, for its icon: few enough that
/// each looks unlike the rest (decisions B-FP2-7).
enum FileKind: Sendable, CaseIterable {
    case folder, application, alias, pdf, image, audio, video, archive, code, text, document

    /// The kind of an item of `type`: worked out as the folder is listed, off
    /// the main actor, by the type's conformances, the narrower kinds first
    /// (source code is text too, a PDF a document). A symbolic link is an
    /// alias, as Finder badges one, whatever it leads to.
    static func of(_ type: UTType, isFolder: Bool, isSymbolicLink: Bool) -> Self {
        if isSymbolicLink { return .alias }
        if isFolder { return .folder }
        let kinds: [(Self, [UTType])] = [
            (.application, [.application, .applicationBundle]),
            (.pdf, [.pdf]),
            (.image, [.image]),
            (.audio, [.audio]),
            (.video, [.movie, .video, .audiovisualContent]),
            (.archive, [.archive, .diskImage]),
            (.code, [.sourceCode, .script, .json, .xml, .yaml, .propertyList]),
            (.text, [.text]),
        ]
        for (kind, types) in kinds where types.contains(where: { type.conforms(to: $0) }) {
            return kind
        }
        return .document
    }

    /// The kind's emoji, where the terminal draws emoji chrome legibly
    /// (`supportsEmojiChrome`). Each is an emoji of default emoji
    /// presentation and East Asian Wide, two cells, needing no variation
    /// selector (the width corpus's `default_emoji` class).
    var emoji: String {
        switch self {
        case .folder: "\u{1F4C1}"  // 📁
        case .application: "\u{1F680}"  // 🚀
        case .alias: "\u{1F517}"  // 🔗
        case .pdf: "\u{1F4D5}"  // 📕
        case .image: "\u{1F304}"  // 🌄
        case .audio: "\u{1F3B5}"  // 🎵
        case .video: "\u{1F3AC}"  // 🎬
        case .archive: "\u{1F4E6}"  // 📦
        case .code: "\u{1F4DC}"  // 📜
        case .text: "\u{1F4DD}"  // 📝
        case .document: "\u{1F4C4}"  // 📄
        }
    }

    /// The SF Symbol drawing the kind, where the terminal's font has them
    /// (`SFSymbol.canRender(named:)`), by the names of the table TUI
    /// bakes (SF Symbols 6 named `doc` `document`, `doc.text`
    /// `text.document` and `doc.richtext` `richtext.page`).
    var symbolName: String {
        switch self {
        case .folder: "folder"
        case .application: "app"
        case .alias: "arrowshape.turn.up.right"
        case .pdf: "richtext.page"
        case .image: "photo"
        case .audio: "music.note"
        case .video: "film"
        case .archive: "archivebox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .text: "text.document"
        case .document: "document"
        }
    }
}
