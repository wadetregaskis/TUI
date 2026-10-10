//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DetachedFromRuntimeTests.swift
//
//  `EnvironmentValues.detachedFromRuntime()` clears every framework object an
//  environment carries — the substrate's own, and the ones the features above
//  it hand down through the substrate's opaque slots (`FeatureObjectSlot`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitNavigation
@testable import TUIkitPresentation
@testable import TUIkitSearch
@testable import TUIkitStyling
@testable import TUIkitView

@MainActor
@Suite("Detaching an environment from the runtime")
struct DetachedFromRuntimeTests {
    /// One object a detached environment must not keep: its name, and whether
    /// an environment holds it.
    private struct Held {
        let name: String
        let isHeld: (EnvironmentValues) -> Bool
    }

    /// Every object `detachedFromRuntime()` cleared before the features' objects
    /// moved into slots — the list it had then, one entry per line it had — so
    /// a slot missed, or a typed accessor that stops going through its slot,
    /// leaves one of these standing and fails here.
    private static let held: [Held] = [
        // `applyRuntimeServices(from:)`.
        Held(name: "keyboardShortcutRegistry") { $0.keyboardShortcutRegistry != nil },
        Held(name: "stateStorage") { $0.stateStorage != nil },
        Held(name: "lifecycle") { $0.lifecycle != nil },
        Held(name: "keyEventDispatcher") { $0.keyEventDispatcher != nil },
        Held(name: "synthesizeKeyEvent") { $0.synthesizeKeyEvent != nil },
        Held(name: "mouseEventDispatcher") { $0.mouseEventDispatcher != nil },
        Held(name: "dragAndDropSession") { $0.dragAndDropSession != nil },
        Held(name: "typedClipboard") { $0.typedClipboard != nil },
        Held(name: "tooltipState") { $0.tooltipState != nil },
        Held(name: "terminalImageStore") { $0.terminalImageStore != nil },
        Held(name: "renderCache") { $0.renderCache != nil },
        Held(name: "preferenceStorage") { $0.preferenceStorage != nil },
        // The render loop's managers and per-frame objects.
        Held(name: "statusBar") { $0.statusBar != nil },
        Held(name: "windowChrome") { $0.windowChrome != nil },
        Held(name: "focusManager") { $0.focusManager != nil },
        Held(name: "paletteManager") { $0.paletteManager != nil },
        Held(name: "appearanceManager") { $0.appearanceManager != nil },
        Held(name: "notificationService") { $0.notificationService != nil },
        Held(name: "cursorTimer") { $0.cursorTimer != nil },
        Held(name: "animationScheduler") { $0.animationScheduler != nil },
        Held(name: "volatileReadTracker") { $0.volatileReadTracker != nil },
        // Handed down to a subtree by what encloses it.
        Held(name: "scrollContentWindow") { $0.scrollContentWindow != nil },
        Held(name: "scrollToRegistry") { $0.scrollToRegistry != nil },
        Held(name: "scrollPositionBinding") { $0.scrollPositionBinding != nil },
        Held(name: "scrollObservers") { !$0.scrollObservers.isEmpty },
        Held(name: "navigationCoordinator") { $0.navigationCoordinator != nil },
        Held(name: "dismissalGate") { $0.dismissalGate != nil },
        Held(name: "dialogSuppression") { $0.dialogSuppression != nil },
        Held(name: "menuRowSink") { $0.menuRowSink != nil },
        Held(name: "assignedFocusID") { $0.assignedFocusID != nil },
        Held(name: "assignedKeyboardShortcut") { $0.assignedKeyboardShortcut != nil },
        Held(name: "focusHandoffOffer") { $0.focusHandoffOffer != nil },
        Held(name: "preferredFocusOffer") { $0.preferredFocusOffer != nil },
        Held(name: "listRowEditRestrictions") { $0.listRowEditRestrictions != nil },
        Held(name: "searchDismissal") { $0.searchDismissal != nil },
        Held(name: "searchFocusOffer") { $0.searchFocusOffer != nil },
        Held(name: "searchScopeBar") { $0.searchScopeBar != nil },
    ]

    /// An environment holding every one of ``held``, each set through the
    /// accessor the framework sets it through.
    private static func environmentHoldingEverything(tui: TUIContext, appState: AppState) -> EnvironmentValues {
        var environment = EnvironmentValues()
        tui.synthesizeKeyEvent = { _ in }
        environment.applyRuntimeServices(from: tui)
        environment.statusBar = StatusBarState(appState: appState)
        environment.windowChrome = WindowChromeState()
        environment.focusManager = FocusManager()
        environment.paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: {})
        environment.appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: {})
        environment.notificationService = NotificationService()
        environment.cursorTimer = CursorTimer(renderNotifier: appState)
        environment.animationScheduler = AnimationScheduler()
        environment.volatileReadTracker = VolatileReadTracker()
        environment.scrollContentWindow = ScrollContentWindow(offset: 0, viewportHeight: 4)
        environment.scrollToRegistry = ScrollToRegistry()
        environment.scrollPositionBinding = ScrollPositionBinding(.constant(ScrollPosition()), anchor: nil)
        environment.scrollObservers = ScrollObservers(phase: [ScrollPhaseObserver { _, _, _ in }])
        environment.navigationCoordinator = NavigationCoordinator()
        environment.dismissalGate = DismissalGate()
        environment.dialogSuppression = DialogSuppression()
        environment.menuRowSink = MenuRowSink()
        environment.assignedFocusID = AssignedFocusID(id: "field")
        environment.assignedKeyboardShortcut = KeyboardShortcutAssignment(KeyboardShortcut("k"))
        let focusStore = FocusStateStore(emptyValue: false)
        environment.focusHandoffOffer = FocusHandoffOffer(store: focusStore, value: true)
        environment.preferredFocusOffer = PreferredFocusOffer(namespace: Namespace().wrappedValue)
        environment.listRowEditRestrictions = RowEditRestrictions()
        environment.searchDismissal = SearchDismissal()
        environment.searchFocusOffer = TypedSearchFocusOffer(store: focusStore, value: true)
        environment.searchScopeBar = SearchScopeBar()
        return environment
    }

    @Test("Every framework object an environment held, the features' slotted ones included, is gone once detached")
    func clearsEveryObject() {
        let tui = TUIContext()
        let appState = AppState()
        let environment = Self.environmentHoldingEverything(tui: tui, appState: appState)
        // The fixture: each is there to clear, or its expectation below would
        // pass on an object never set.
        for object in Self.held {
            #expect(object.isHeld(environment), "the fixture sets \(object.name)")
        }

        let detached = environment.detachedFromRuntime()

        for object in Self.held {
            #expect(!object.isHeld(detached), "\(object.name) survived detaching")
        }
    }

    /// The substrate side alone: whatever a feature put in a slot, under any
    /// type, detaching clears — the slot's owner need not be one the clear knows.
    @Test("Detaching clears every feature-object slot, whatever its object")
    func clearsEverySlot() {
        final class Sentinel {}
        var environment = EnvironmentValues()
        for slot in FeatureObjectSlot.allCases {
            environment[featureObject: slot] = Sentinel()
            #expect(environment[featureObject: slot] != nil, "the fixture fills \(slot)")
        }

        let detached = environment.detachedFromRuntime()

        for slot in FeatureObjectSlot.allCases {
            #expect(detached[featureObject: slot] == nil, "\(slot) survived detaching")
        }
    }

    /// Each feature's typed accessor reads back what it wrote, and reads `nil`
    /// from a slot holding an object of another type rather than trapping —
    /// the slot is the feature's, but it is typed `AnyObject?`.
    @Test("A feature's typed accessor reads its own object back, and nil for a stranger's")
    func typedAccessorsRoundTrip() {
        var environment = EnvironmentValues()
        let coordinator = NavigationCoordinator()
        environment.navigationCoordinator = coordinator
        #expect(environment.navigationCoordinator === coordinator)
        #expect(environment[featureObject: .navigationCoordinator] === coordinator)

        environment[featureObject: .navigationCoordinator] = SearchScopeBar()
        #expect(environment.navigationCoordinator == nil)
    }

    /// The notification service is the window chrome's, so its public
    /// accessor is a typed view of the `.notificationService` slot — what lets
    /// detaching clear it without the substrate naming the chrome's type. An
    /// accessor that went back to a key of its own would still round-trip, and
    /// would only leak once nothing cleared that key by name; this catches it
    /// at once.
    @Test("The notification service's accessor reads and writes the substrate's slot")
    func notificationServiceIsSlotted() {
        var environment = EnvironmentValues()
        let service = NotificationService()
        environment.notificationService = service
        #expect(environment.notificationService === service)
        #expect(environment[featureObject: .notificationService] === service)

        environment[featureObject: .notificationService] = SearchScopeBar()
        #expect(environment.notificationService == nil)
    }
}
