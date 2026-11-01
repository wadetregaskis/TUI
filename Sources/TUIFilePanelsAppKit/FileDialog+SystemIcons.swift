//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDialog+SystemIcons.swift
//
//  `fileDialogSystemIcons()`: the file panels' items drawn with their own
//  icons, the Finder's, from `NSWorkspace` — here, in TUIFilePanelsAppKit,
//  because the file panels may not import AppKit (decisions A-FP2-1, the
//  owner's option 2; `Exports.swift` in this module says why it is not in
//  TUIAppKit either).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)
    import AppKit
    import TUIAppKit
    import TUIBitmaps
    import TUIFilePanels
    import TUIFoundation
    import UniformTypeIdentifiers

    extension View {
        /// Draws each item of the `fileImporter`, `fileExporter` and
        /// `fileMover` panels beneath this view with its own icon, as the
        /// Finder draws it (`NSWorkspace`'s), where the terminal draws
        /// pictures. A TUI-specific modifier, built on `fileDialogIcon(_:)`.
        ///
        /// ```swift
        /// .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { … }
        /// .fileDialogSystemIcons()
        /// ```
        ///
        /// Pictures draw where the terminal answered TUI's graphics
        /// handshake (`KittyGraphics.isSupported`: Ghostty, kitty, iTerm2,
        /// WezTerm) and `terminalGraphics(_:)` has not turned them off, as an
        /// `Image` decides; elsewhere a panel draws its own icons, the kinds'
        /// emoji or SF Symbols, since a two-cell icon drawn in glyphs is no
        /// icon at all.
        ///
        /// A folder, a package (an application) and a symbolic link are each
        /// asked for their own icon, which may be a custom one; any other file
        /// is drawn with its type's, asked for once per type. The icons are
        /// kept while the view lives, so each is sent to the terminal once.
        nonisolated public func fileDialogSystemIcons() -> some View {
            FileDialogSystemIconsModifier(content: self)
        }
    }

    /// The icons `fileDialogSystemIcons()` draws, kept: `NSWorkspace` makes a
    /// new `NSImage` on each call, and an `Image(nsImage:)` is named by its
    /// `NSImage`'s address, so an icon asked for afresh would be a new picture,
    /// read and sent to the terminal again, on every frame.
    ///
    /// Main-actor state: asked from a panel's rows as they draw. `NSWorkspace`
    /// may be asked from any thread; the main actor is where the rows are.
    @MainActor
    final class FileDialogSystemIcons {
        nonisolated init() {}

        /// The size, in points, the icons are drawn out of the `NSImage` at:
        /// more pixels than two cells hold at a Retina terminal's cell size
        /// (about 16 by 34), which the picture path scales down to the cells.
        static let pointSize = 32

        /// How many icons are kept before the store starts again: a folder's
        /// own icon is kept by its path, and a session that browses the whole
        /// disk would otherwise keep one for every folder it passed.
        static let limit = 512

        private var kept: [String: NSImage] = [:]

        /// Whether the panel's rows draw pictures: the terminal takes them,
        /// and the app has not turned them off.
        static func drawsPictures(terminalGraphics: Bool, supported: Bool = KittyGraphics.isSupported) -> Bool {
            terminalGraphics && supported
        }

        /// The key an item's icon is kept under: its path where the item may
        /// have an icon of its own — a folder (the Finder's Downloads, a
        /// folder given a custom icon), a package such as an application, a
        /// symbolic link with its badge — and otherwise its type's identifier,
        /// which every file of the type shares.
        static func key(for url: URL, type: UTType) -> String {
            let ownIcon = [UTType.directory, .package, .symbolicLink].contains { type.conforms(to: $0) }
            return ownIcon ? "path:" + url.path : "type:" + type.identifier
        }

        /// The icon of the item at `url`, of `type`: kept, or asked for and
        /// kept.
        func nsImage(for url: URL, type: UTType) -> NSImage {
            let key = Self.key(for: url, type: type)
            if let image = kept[key] { return image }
            let image =
                key.hasPrefix("path:")
                ? NSWorkspace.shared.icon(forFile: url.path) : NSWorkspace.shared.icon(for: type)
            image.size = NSSize(width: Self.pointSize, height: Self.pointSize)
            if kept.count >= Self.limit { kept.removeAll(keepingCapacity: true) }
            kept[key] = image
            return image
        }

        /// The view a panel draws the icon in: the picture fitted to the two
        /// cells the panel gives it.
        func icon(for url: URL, type: UTType) -> some View {
            Image(nsImage: nsImage(for: url, type: type)).resizable().scaledToFit()
        }
    }

    /// `fileDialogSystemIcons()`: a store of icons of this view's own, and a
    /// `fileDialogIcon(_:)` that draws from it where pictures draw.
    private struct FileDialogSystemIconsModifier<Content: View> {
        let content: Content

        /// The icons, kept for as long as this view lives.
        @State private var icons = FileDialogSystemIcons()

        /// The app's word on pictures, where the panels are presented: the
        /// panel draws in a sheet that inherits it.
        @Environment(\.terminalGraphics) private var terminalGraphics

        @MainActor var body: some View {
            let icons = icons
            let terminalGraphics = terminalGraphics
            return content.fileDialogIcon { url, type in
                // Asked as each row draws, not when the body ran: the
                // graphics handshake may answer after the first frame.
                FileDialogSystemIcons.drawsPictures(terminalGraphics: terminalGraphics)
                    ? icons.icon(for: url, type: type) : nil
            }
        }
    }
    extension FileDialogSystemIconsModifier: View {}
#endif
