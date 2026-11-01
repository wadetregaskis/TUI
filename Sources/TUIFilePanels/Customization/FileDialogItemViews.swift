//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDialogItemViews.swift
//
//  A view an app supplies for each item of the file panels beneath it — its
//  icon (`fileDialogIcon(_:)`) or its preview (`fileDialogPreview(_:)`) — kept
//  so that the environment value compares equal from frame to frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// The views an app draws for a file panel's items, by the identity of the
/// box the modifier keeps its closure in, as
/// ``FileDialogCustomization/URLEnabled`` is: a closure cannot be compared,
/// and an environment value that cannot be compared turns the memos beneath
/// it off.
///
/// Read while the rows draw, so a row the table serves from its memo keeps
/// the view it was drawn with until the row itself changes: an app whose
/// closure starts answering otherwise for the same item sees the new view
/// when the folder is next read.
struct FileDialogItemViews: Equatable {
    /// The box the modifier keeps.
    let box: Box

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.box === rhs.box }

    /// The app's view for `entry`, or `nil` for TUI's own.
    @MainActor
    func view(for entry: FileEntry) -> AnyView? {
        box.make(entry.url, entry.contentType)
    }

    /// The closure a modifier's latest body gave it. Main-actor state: written
    /// by a body, read by a row's.
    final class Box {
        var make: @MainActor (URL, UTType) -> AnyView?

        init(_ make: @escaping @MainActor (URL, UTType) -> AnyView?) {
            self.make = make
        }
    }
}

/// A modifier that hands the panels beneath it an app's views at `keyPath`:
/// the closure kept in a box of this view's own, so the environment value it
/// writes compares equal from frame to frame (``FileDialogItemViews``).
struct FileDialogItemViewsModifier<Content: View> {
    let content: Content
    let keyPath: WritableKeyPath<EnvironmentValues, FileDialogItemViews?>
    let make: @MainActor (URL, UTType) -> AnyView?

    /// The box: the first one made, kept for as long as this view lives.
    @State private var box: FileDialogItemViews.Box

    init(
        content: Content, keyPath: WritableKeyPath<EnvironmentValues, FileDialogItemViews?>,
        make: @escaping @MainActor (URL, UTType) -> AnyView?
    ) {
        self.content = content
        self.keyPath = keyPath
        self.make = make
        _box = State(initialValue: FileDialogItemViews.Box(make))
    }

    @MainActor var body: some View {
        // The box's contents, not the state itself: nothing redraws for it.
        box.make = make
        return content.environment(keyPath, FileDialogItemViews(box: box))
    }
}
extension FileDialogItemViewsModifier: View {}
