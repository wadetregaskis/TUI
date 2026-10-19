//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationHostsToolbar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Environment

/// Environment key for presented content, whose toolbars host themselves.
private struct PresentationHostsToolbarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this subtree is presented content — a sheet's, a full-screen
    /// cover's, a popover's — whose `.toolbar`s draw their items themselves,
    /// round the view they are attached to, rather than putting them in the
    /// window's bars.
    ///
    /// Set by the presenters for the content they present. The window's bars
    /// are drawn inert while a presentation holds the input, so an item a
    /// sheet put there — SwiftUI's
    /// `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { … } } }`
    /// on a sheet's content — was a dead button in the window's top bar:
    /// unreachable by key, click or Tab, and the bar appeared a frame after the
    /// sheet did and went a frame after it closed.
    ///
    /// Its `.navigationTitle` is not the window's either
    /// (`PreferenceModifier`'s offer to the window chrome): a sheet's title is
    /// the sheet's.
    package var presentationHostsToolbar: Bool {
        get { self[PresentationHostsToolbarKey.self] }
        set { self[PresentationHostsToolbarKey.self] = newValue }
    }

    /// Makes this subtree presented content whose `.toolbar`s draw their items
    /// round the views they are attached to — a popover's — and not in the
    /// rows of a sheet or a cover it is presented over.
    ///
    /// A sheet hosts its toolbar's items at its own edges, wherever in it they
    /// are declared (`presentationToolbar`, TUIkitChrome), and a popover over
    /// it inherited that host with the rest of the sheet's environment: the
    /// popover's items went to the sheet's rows, a frame later, and were
    /// missing from the popover, and its `.toolbarVisibility(_:for:)` hid
    /// the sheet's rows.
    package mutating func hostToolbarsRoundTheirViews() {
        presentationHostsToolbar = true
        self[featureObject: .presentationToolbar] = nil
    }
}
