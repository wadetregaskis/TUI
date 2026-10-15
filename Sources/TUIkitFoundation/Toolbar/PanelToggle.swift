//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PanelToggle.swift
//
//  A panel's toggle as a toolbar's button works it: what a NavigationSplitView
//  publishes for its sidebar, and `DefaultToolbarItem(kind: .sidebarToggle)`
//  draws a button for. Here, below the modules that publish it
//  (TUIkitNavigation) and draw it (TUIkitChrome), so both can name it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Panel Toggle

/// A panel's toggle, as a toolbar's button for it shows and works it: whether
/// the panel is showing, and what showing or hiding it does.
///
/// A ``NavigationSplitView`` publishes its sidebar's for the views in its
/// columns (``EnvironmentValues/sidebarToggleScope``) — so a
/// ``DefaultToolbarItem`` declared there toggles that split —
/// and offers it to the window (``PanelToggleOffer/offer(_:itemIdentity:context:)``)
/// for an item declared round any split view.
package struct PanelToggle: Sendable, Equatable {
    /// The panels a toolbar can toggle.
    package enum Panel: Sendable, Hashable {
        /// A ``NavigationSplitView``'s sidebar, the leading column.
        case sidebar
    }

    /// What a toggle does, by reference: kept by its owner across renders, so
    /// two renders' toggles compare equal while the closure is brought up to
    /// date, as ``DismissAction``'s box is.
    ///
    /// `@unchecked Sendable`: `perform` is written by the owner's render and
    /// called by a button's action, both on the main actor.
    package final class Action: @unchecked Sendable {
        /// Shows the panel if it is hidden, hides it if it is showing.
        package var perform: () -> Void { get { _perform } set { _perform = newValue } }

        /// ``perform``'s storage: private, under the `package` accessor
        /// (CONTRIBUTING.md, "Crossing a module boundary").
        private var _perform: () -> Void = {}

        package init() {}
    }

    /// Which panel this toggles.
    package let panel: Panel

    /// The identity of the view whose panel it is: the split view's.
    package let owner: ViewIdentity

    /// Whether the panel is showing.
    package let isShown: Bool

    /// What toggling does.
    package let action: Action

    package init(panel: Panel, owner: ViewIdentity, isShown: Bool, action: Action) {
        self.panel = panel
        self.owner = owner
        self.isShown = isShown
        self.action = action
    }

    /// Where a toolbar's button for a panel finds the toggle it works.
    package enum Scope: Sendable, Equatable {
        /// Outside any view that owns such a panel: the window's
        /// (``WindowChromeState/panelToggle(_:)``).
        case window
        /// In a split view's column: that split's, or none where the split
        /// has no toggle — an item declared in a split whose toggle was
        /// removed does not reach past it to another's.
        case split(PanelToggle?)
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.panel == rhs.panel && lhs.owner == rhs.owner && lhs.isShown == rhs.isShown && lhs.action === rhs.action
    }

    /// The button's arrow: which way the panel's edge moves. A sidebar,
    /// against the leading edge, goes with ◀ and comes back with ▶, as the
    /// split view's own handles draw it.
    package var arrow: String {
        isShown ? TerminalSymbols.leftArrow : TerminalSymbols.rightArrow
    }

    /// What the button's help says it does: SwiftUI's own labels for its
    /// sidebar button.
    package var helpText: String {
        LocalizationService.shared.string(
            for: isShown ? LocalizationKey.Label.hideSidebar : LocalizationKey.Label.showSidebar)
    }

    /// What Return does on the button, for the status bar's key hints.
    package var activationLabel: String {
        LocalizationService.shared.string(
            for: isShown ? LocalizationKey.StatusBar.hideSidebar : LocalizationKey.StatusBar.showSidebar)
    }
}

// MARK: - The Window's Offer

/// A panel's toggle offered to the window, as a render offers it and as a value
/// memo serving that render offers it again — see `EffectJournal`.
///
/// The window's offers are emptied every walk
/// (``WindowChromeState/beginWalk()``), and a split view is built to be served
/// from a memo: an offer made only by its render left the window with no
/// sidebar toggle on a frame that served the split, and the top bar's button,
/// and any placed round the split, went.
package enum PanelToggleOffer {
    /// The journal kind of an offer.
    static let kind = EffectJournal.Kind("panelToggleOffer")

    /// Offers `toggle` as the window's toggle for its panel
    /// (``WindowChromeState/offerPanelToggle(_:environment:itemIdentity:)``),
    /// with `context`'s environment and `itemIdentity` for a bar's button to
    /// draw it with — and records the offer for a memo to make again. Nothing
    /// in presented content, whose bars are its own.
    @MainActor
    package static func offer(_ toggle: PanelToggle, itemIdentity: ViewIdentity, context: RenderContext) {
        guard let chrome = context.environment.windowChrome, !context.environment.presentationHostsToolbar
        else { return }
        let environment = context.environment
        chrome.offerPanelToggle(toggle, environment: environment, itemIdentity: itemIdentity)
        environment.volatileReadTracker?.recordReplayableEffect()
        if let journal = context.recordingEffectJournal {
            journal.append(
                EffectJournal.Entry(kind: kind, channelToken: environment.keyChannelToken) { replay in
                    replay.environment.windowChrome?.offerPanelToggle(
                        toggle, environment: environment, itemIdentity: itemIdentity)
                })
        }
    }
}

// MARK: - Environment

/// Environment key for where a sidebar button finds its toggle.
private struct SidebarToggleScopeKey: EnvironmentKey {
    static let defaultValue = PanelToggle.Scope.window
}

extension EnvironmentValues {
    /// Where a toolbar's button for `panel` declared here finds its toggle.
    package func panelToggleScope(_ panel: PanelToggle.Panel) -> PanelToggle.Scope {
        switch panel {
        case .sidebar: sidebarToggleScope
        }
    }

    /// Where a toolbar's sidebar button declared here finds the toggle it
    /// works: the innermost ``NavigationSplitView`` this view is in a column
    /// of, which has none where its toggle was removed or it is disabled, or
    /// outside every split view, the window's.
    package var sidebarToggleScope: PanelToggle.Scope {
        get { self[SidebarToggleScopeKey.self] }
        set { self[SidebarToggleScopeKey.self] = newValue }
    }
}
