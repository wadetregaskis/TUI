//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelIcon.swift
//
//  The icon before an item's name in a file panel: an emoji, or an SF
//  Symbol, of the item's kind — whichever the terminal draws — or none.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// The glyphs a file panel draws its icons in, in the terminal it is in.
enum FilePanelIcon: Equatable {
    /// The kinds' emoji (``FileKind/emoji``): where the terminal draws emoji
    /// chrome legibly, as a search field draws its magnifier.
    case emoji
    /// The kinds' SF Symbols (``FileKind/symbolName``): where the terminal's
    /// font has them and emoji are not drawn.
    case symbols
    /// None: a folder's name ends in a slash instead, as `ls -F` marks one,
    /// and the terminal file managers that draw no icons do.
    case none

    /// The icons drawn where emoji chrome is (or is not) drawn legibly, and
    /// the SF Symbols font is (or is not) installed.
    static func resolve(supportsEmojiChrome: Bool, symbolsRender: Bool) -> Self {
        if supportsEmojiChrome { return .emoji }
        return symbolsRender ? .symbols : .none
    }

    /// Whether the SF Symbols draw here: the font installed (on Apple
    /// platforms; never elsewhere) and every kind's symbol known. Asked once:
    /// the font does not come and go while the app runs.
    static let symbolsRender: Bool =
        SFSymbol.isFontAvailable && FileKind.allCases.allSatisfy { SFSymbol.canRender(named: $0.symbolName) }
}

private struct FilePanelIconsKey: EnvironmentKey {
    static let defaultValue: FilePanelIcon? = nil
}

extension EnvironmentValues {
    /// The icons a file panel draws, where something pins them: `nil`, as
    /// everywhere but in tests, for the terminal's own
    /// (``FilePanelIcon/resolve(supportsEmojiChrome:symbolsRender:)``). The
    /// SF Symbols' font is the machine's, not the environment's, so a test
    /// pins the icons rather than draw what its host happens to have.
    var filePanelIcons: FilePanelIcon? {
        get { self[FilePanelIconsKey.self] }
        set { self[FilePanelIconsKey.self] = newValue }
    }
}

/// An item's name cell: the app's icon for it (`fileDialogIcon(_:)`), else
/// its kind's where the terminal draws one, then its name — bold for a
/// folder, and ending in a slash where no icon says it is one — in the faint
/// tier where the row is dimmed.
struct FilePanelNameCell: View {
    let entry: FileEntry

    @Environment(\.supportsEmojiChrome) private var supportsEmojiChrome

    @Environment(\.filePanelIcons) private var pinned

    /// The app's icons, where it supplies them.
    @Environment(\.fileDialogIcon) private var appIcons

    var body: some View {
        if let icon = appIcons?.icon(for: entry) {
            // In the cells an emoji icon takes, so the names line up whatever
            // the app draws.
            HStack(spacing: 1) {
                icon.frame(width: 2, height: 1)
                FilePanelColumns.cell(entry.name, entry, bold: entry.isFolder)
            }
        } else {
            kindIcon
        }
    }

    /// The kind's icon in the glyphs the terminal draws, then the name.
    @ViewBuilder private var kindIcon: some View {
        let icons =
            pinned
            ?? FilePanelIcon.resolve(
                supportsEmojiChrome: supportsEmojiChrome, symbolsRender: FilePanelIcon.symbolsRender)
        switch icons {
        case .emoji:
            HStack(spacing: 1) {
                Text(verbatim: entry.fileKind.emoji)
                FilePanelColumns.cell(entry.name, entry, bold: entry.isFolder)
            }
        case .symbols:
            HStack(spacing: 1) {
                FilePanelColumns.cell(SFSymbol.glyph(named: entry.fileKind.symbolName) ?? "", entry)
                FilePanelColumns.cell(entry.name, entry, bold: entry.isFolder)
            }
        case .none:
            FilePanelColumns.cell(entry.displayName, entry, bold: entry.isFolder)
        }
    }
}
