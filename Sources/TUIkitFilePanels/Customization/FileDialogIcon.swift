//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileDialogIcon.swift
//
//  `fileDialogIcon(_:)`: an app's own icon for each item of the file panels
//  beneath it, drawn in place of TUIkit's glyphs (decisions A-FP2-1, the
//  owner's option 2).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// The icons an app draws for a file panel's items (`fileDialogIcon(_:)`),
/// by the identity of the box the modifier keeps its closure in, as
/// ``FileDialogCustomization/URLEnabled`` is: a closure cannot be compared,
/// and an environment value that cannot be compared turns the memos beneath
/// it off.
///
/// Unlike the URL predicate it is read while the rows draw, so a row the
/// table serves from its memo keeps the icon it was drawn with until the row
/// itself changes: an app whose closure starts answering otherwise for the
/// same item sees the new icon when the folder is next read.
struct FileDialogIconProvider: Equatable, @unchecked Sendable {
    /// The box the modifier keeps.
    let box: Box

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.box === rhs.box }

    /// The app's icon for `entry`, or `nil` for TUIkit's own.
    @MainActor
    func icon(for entry: FileEntry) -> AnyView? {
        box.icon(entry.url, entry.contentType)
    }

    /// The closure a modifier's latest body gave it. Main-actor state: written
    /// by a body, read by a row's.
    final class Box {
        var icon: @MainActor (URL, UTType) -> AnyView?

        init(_ icon: @escaping @MainActor (URL, UTType) -> AnyView?) {
            self.icon = icon
        }
    }
}

private struct FileDialogIconKey: EnvironmentKey {
    static let defaultValue: FileDialogIconProvider? = nil
}

extension EnvironmentValues {
    /// The icons an app draws for the items of the file panels beneath
    /// (`fileDialogIcon(_:)`), or `nil` for TUIkit's own (``FilePanelIcon``).
    var fileDialogIcon: FileDialogIconProvider? {
        get { self[FileDialogIconKey.self] }
        set { self[FileDialogIconKey.self] = newValue }
    }
}

extension View {
    /// Draws each item of the `fileImporter`, `fileExporter` and `fileMover`
    /// panels beneath this view with an icon the app supplies. A TUI-specific
    /// modifier: SwiftUI's panels are the system's, which draw the system's
    /// icons themselves.
    ///
    /// The closure is given each item's URL and content type and returns the
    /// view to draw before its name, in the two cells, one row high, an emoji
    /// icon takes; `nil` keeps TUIkit's own icon for that item — the kind's
    /// emoji, SF Symbol or none, whichever the terminal draws.
    ///
    /// ```swift
    /// .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { … }
    /// .fileDialogIcon { url, type in
    ///     type.conforms(to: .image) ? thumbnail(of: url) : nil
    /// }
    /// ```
    ///
    /// It is called on the main actor as rows are drawn, so it should be
    /// quick, keeping what it makes: an `Image` made afresh from new pixels
    /// for every call is a new picture each frame. On macOS,
    /// `fileDialogSystemIcons()` in TUIkitAppKit installs one that draws each
    /// item's own icon, the Finder's, where the terminal draws pictures.
    ///
    /// - Parameter icon: The view to draw for the item at a URL, of a content
    ///   type, or `nil` for TUIkit's own icon.
    public func fileDialogIcon<Icon: View>(_ icon: @escaping @MainActor (URL, UTType) -> Icon?) -> some View {
        FileDialogIconModifier(content: self) { url, type in icon(url, type).map { AnyView($0) } }
    }
}

/// `fileDialogIcon(_:)`: the closure kept in a box of this view's own, so the
/// environment value it writes compares equal from frame to frame
/// (``FileDialogIconProvider``).
private struct FileDialogIconModifier<Content: View>: View {
    let content: Content
    let icon: @MainActor (URL, UTType) -> AnyView?

    /// The box: the first one made, kept for as long as this view lives.
    @State private var box: FileDialogIconProvider.Box

    init(content: Content, icon: @escaping @MainActor (URL, UTType) -> AnyView?) {
        self.content = content
        self.icon = icon
        _box = State(initialValue: FileDialogIconProvider.Box(icon))
    }

    var body: some View {
        // The box's contents, not the state itself: nothing redraws for it.
        box.icon = icon
        return content.environment(\.fileDialogIcon, FileDialogIconProvider(box: box))
    }
}
