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

import Foundation
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
        /// An `inspector(isPresented:content:)`'s column, the trailing one.
        case inspector
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

        /// The name the last labelled bar button for the panel drawn gave it
        /// (`DefaultToolbarItem(kind:placement:label:)`), its label's text; `nil`
        /// where the last one drawn had no label.
        package var labelText: String? { get { _labelText } set { _labelText = newValue } }

        /// ``labelText``'s storage.
        private var _labelText: String?

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
    /// split view's own handles draw it; an inspector, against the trailing
    /// edge, the other way round.
    package var arrow: String {
        (panel == .sidebar) == isShown ? TerminalSymbols.leftArrow : TerminalSymbols.rightArrow
    }

    /// What the button's help says it does — SwiftUI's own labels for its
    /// sidebar button, and the same words for an inspector — naming the panel
    /// `name` where a toolbar item gave it one.
    package func helpText(named name: String?) -> String {
        Self.helpText(for: panel, hides: isShown, named: name)
    }

    /// What Return does on the button, for the status bar's key hints, naming
    /// the panel `name` where a toolbar item gave it one.
    package func activationLabel(named name: String?) -> String {
        Self.activationLabel(for: panel, hides: isShown, named: name)
    }

    /// The name the panel's labelled bar button gave it, while a bar draws a
    /// button for it: what the owner's own handles' key hints call it.
    package func name(in context: RenderContext) -> String? {
        Self.name(of: owner, action: action, in: context)
    }

    /// The name a labelled bar button gave the panel owned by the view at
    /// `owner`, whose toggle's action is `action`, while a bar draws a button
    /// for it (``WindowChromeState/hasBarToggle(for:)``).
    package static func name(of owner: ViewIdentity, action: Action, in context: RenderContext) -> String? {
        context.environment.windowChrome?.hasBarToggle(for: owner) == true ? action.labelText : nil
    }

    /// The help of a button that hides `panel` (`hides`) or shows it.
    package static func helpText(for panel: Panel, hides: Bool, named name: String?) -> String {
        if let name {
            return LocalizationService.shared.string(
                for: hides ? LocalizationKey.Label.hideNamedPanel : .showNamedPanel
            ).replacingOccurrences(of: "%@", with: name)
        }
        let key: LocalizationKey.Label =
            switch panel {
            case .sidebar: hides ? .hideSidebar : .showSidebar
            case .inspector: hides ? .hideInspector : .showInspector
            }
        return LocalizationService.shared.string(for: key)
    }

    /// The key hint of a control that hides `panel` (`hides`) or shows it.
    package static func activationLabel(for panel: Panel, hides: Bool, named name: String?) -> String {
        if let name {
            return LocalizationService.shared.string(
                for: hides ? LocalizationKey.StatusBar.hideNamedPanel : .showNamedPanel
            ).replacingOccurrences(of: "%@", with: name)
        }
        let key: LocalizationKey.StatusBar =
            switch panel {
            case .sidebar: hides ? .hideSidebar : .showSidebar
            case .inspector: hides ? .hideInspector : .showInspector
            }
        return LocalizationService.shared.string(for: key)
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
        case .inspector: inspectorToggleScope
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

/// Environment key for where an inspector button finds its toggle.
private struct InspectorToggleScopeKey: EnvironmentKey {
    static let defaultValue = PanelToggle.Scope.window
}

/// Environment key for the toggle of the pane a split view's last divider
/// hides: an inspector's column.
private struct TrailingPaneToggleKey: EnvironmentKey {
    static let defaultValue: PanelToggle? = nil
}

extension EnvironmentValues {
    /// Where a toolbar's inspector button declared here finds the toggle it
    /// works: the innermost `inspector(isPresented:content:)` this view is in
    /// the content or the inspector of, which has none where its toggle was
    /// removed, or outside every inspector, the window's.
    package var inspectorToggleScope: PanelToggle.Scope {
        get { self[InspectorToggleScopeKey.self] }
        set { self[InspectorToggleScopeKey.self] = newValue }
    }

    /// The toggle of the pane after an ``HSplitView``'s last divider, which
    /// draws a ▶ that hides it: set by an inspector for the split it is the
    /// last pane of, and cleared by the split for its panes.
    package var trailingPaneToggle: PanelToggle? {
        get { self[TrailingPaneToggleKey.self] }
        set { self[TrailingPaneToggleKey.self] = newValue }
    }
}
