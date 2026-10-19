//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FeatureObjectSlots.swift
//
//  The environment's places for the objects a feature above the substrate
//  hands down to the views it draws, which the substrate clears without
//  naming their types.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The slots

/// A place in the environment for one object that a feature above the
/// substrate hands down to the views it draws: a navigation stack's
/// coordinator, a dialog's suppression toggle, a searchable's dismissal, focus
/// offer and scope bar, the app's notification service, which the window
/// chrome's notification host draws, the app's scene presenter, which the
/// menu bar's Window menu reads, and the toolbar items a sheet hosts.
///
/// ``EnvironmentValues/detachedFromRuntime()`` has to clear these objects, as
/// it clears the substrate's own, and it cannot name their types: each belongs
/// to its feature, and once TUIkit is split into modules the feature sits above
/// the substrate, which must not name anything above it. So the substrate
/// declares a slot for each, typed `AnyObject?`, and clears every slot, while
/// the feature keeps the typed accessor over its own slot — the
/// `navigationCoordinator` property over the `.navigationCoordinator` slot —
/// so nothing that reads or writes the object changes. An environment modifier that writes one
/// writes it through that accessor, so its value is still compared by the
/// accessor's type, and the memos below it keep working.
///
/// A fixed set, which is NOT a registry the features fill as they run: a key
/// written by a route that skipped registering would never be detached, and
/// nothing would say so. Every slot here is cleared whether or not anything
/// wrote it, and a slot cannot be added without joining ``allCases``, which
/// is what the clear walks.
package enum FeatureObjectSlot: CaseIterable {
    /// The enclosing `NavigationStack`'s coordinator.
    case navigationCoordinator
    /// The suppression toggle the dialogs presented in a subtree show.
    case dialogSuppression
    /// The search `dismissSearch` ends.
    case searchDismissal
    /// The `searchFocused` binding for the nearest searchable's field.
    case searchFocusOffer
    /// The scopes for the nearest searchable's field.
    case searchScopeBar
    /// The app's `NotificationService`, which the run loop publishes every
    /// frame for the window chrome's notification host to draw.
    case notificationService
    /// The app's scene presenter (TUIkitApp), which the run loop publishes
    /// every frame for the menu bar's Window menu to read.
    case scenePresenter
    /// The toolbar items a sheet or a cover hosts at its edges (TUIkitChrome's
    /// `PresentationToolbarItems`).
    case presentationToolbar
}

// MARK: - Storage

/// One environment key per slot: the storage is keyed by a key's TYPE, so each
/// slot needs a type of its own. `AnyObject?`, the one type every slot shares,
/// is all the substrate knows of what is in it.
private enum FeatureObjectSlotKey {
    struct NavigationCoordinatorSlot: EnvironmentKey {
        // Computed: a stored `AnyObject?` is not `Sendable`, and this is `nil`.
        static var defaultValue: AnyObject? { nil }
    }

    struct DialogSuppressionSlot: EnvironmentKey {
        static var defaultValue: AnyObject? { nil }
    }

    struct SearchDismissalSlot: EnvironmentKey {
        static var defaultValue: AnyObject? { nil }
    }

    struct SearchFocusOfferSlot: EnvironmentKey {
        static var defaultValue: AnyObject? { nil }
    }

    struct SearchScopeBarSlot: EnvironmentKey {
        static var defaultValue: AnyObject? { nil }
    }

    struct NotificationServiceSlot: EnvironmentKey {
        static var defaultValue: AnyObject? { nil }
    }

    struct ScenePresenterSlot: EnvironmentKey {
        static var defaultValue: AnyObject? { nil }
    }

    struct PresentationToolbarSlot: EnvironmentKey {
        static var defaultValue: AnyObject? { nil }
    }
}

extension EnvironmentValues {
    /// The object in `slot`, or `nil` where nothing put one there.
    ///
    /// For the feature that owns the slot, under its typed accessor; for
    /// ``detachedFromRuntime()``, which clears every slot; and for a popover,
    /// whose content must not inherit the toolbar host of a sheet it is over
    /// (``hostToolbarsRoundTheirViews()``). Nothing else reads or writes one.
    package subscript(featureObject slot: FeatureObjectSlot) -> AnyObject? {
        get {
            switch slot {
            case .navigationCoordinator: self[FeatureObjectSlotKey.NavigationCoordinatorSlot.self]
            case .dialogSuppression: self[FeatureObjectSlotKey.DialogSuppressionSlot.self]
            case .searchDismissal: self[FeatureObjectSlotKey.SearchDismissalSlot.self]
            case .searchFocusOffer: self[FeatureObjectSlotKey.SearchFocusOfferSlot.self]
            case .searchScopeBar: self[FeatureObjectSlotKey.SearchScopeBarSlot.self]
            case .notificationService: self[FeatureObjectSlotKey.NotificationServiceSlot.self]
            case .scenePresenter: self[FeatureObjectSlotKey.ScenePresenterSlot.self]
            case .presentationToolbar: self[FeatureObjectSlotKey.PresentationToolbarSlot.self]
            }
        }
        set {
            switch slot {
            case .navigationCoordinator: self[FeatureObjectSlotKey.NavigationCoordinatorSlot.self] = newValue
            case .dialogSuppression: self[FeatureObjectSlotKey.DialogSuppressionSlot.self] = newValue
            case .searchDismissal: self[FeatureObjectSlotKey.SearchDismissalSlot.self] = newValue
            case .searchFocusOffer: self[FeatureObjectSlotKey.SearchFocusOfferSlot.self] = newValue
            case .searchScopeBar: self[FeatureObjectSlotKey.SearchScopeBarSlot.self] = newValue
            case .notificationService: self[FeatureObjectSlotKey.NotificationServiceSlot.self] = newValue
            case .scenePresenter: self[FeatureObjectSlotKey.ScenePresenterSlot.self] = newValue
            case .presentationToolbar: self[FeatureObjectSlotKey.PresentationToolbarSlot.self] = newValue
            }
        }
    }
}
