//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusSectionFiledIDTests.swift
//
//  A section checks a registration for a duplicate against its count of the
//  ids it holds, not by a scan of the ring (H-99, FOCUS-7). These pin that the
//  count answers as the scan did: a duplicate is dropped, a taken-back or
//  unregistered id may be filed again, and a handler repointed after it was
//  filed answers to its new id, not its old one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// A persisted handler: one object across frames, whose id the control may
/// repoint.
private final class Repointable: PersistedFocusable {
    private(set) var focusID: String
    var canBeFocused: Bool { true }

    init(_ focusID: String) { self.focusID = focusID }

    func repoint(focusID: String) { self.focusID = focusID }
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
    func onFocusReceived() {}
    func onFocusLost() {}
}

@MainActor
@Suite("A focus section's count of filed ids")
struct FocusSectionFiledIDTests {
    private func ids(_ section: FocusSection) -> [String] { section.focusables.map(\.focusID) }

    @Test("A duplicate id is filed once, in the place it was first filed")
    func duplicateFiledOnce() {
        let section = FocusSection(id: "s")
        for id in ["a", "b", "a", "c", "b"] { section.register(MockFocusable(id: id)) }
        #expect(ids(section) == ["a", "b", "c"])
    }

    @Test("An id taken back, unregistered or cleared can be filed again")
    func removedIDsFileAgain() {
        let section = FocusSection(id: "s")
        let b = MockFocusable(id: "b")
        for element in [MockFocusable(id: "a"), b, MockFocusable(id: "c")] { section.register(element) }

        section.unfile(2..<3)
        section.register(MockFocusable(id: "c"))
        #expect(ids(section) == ["a", "b", "c"])

        section.unregister(b)
        section.register(MockFocusable(id: "b"))
        #expect(ids(section) == ["a", "c", "b"])

        section.clearFocusables()
        section.register(MockFocusable(id: "a"))
        #expect(ids(section) == ["a"])
    }

    @Test("A reserved place holds its id until its owner registers into it")
    func reservationHoldsItsID() {
        let section = FocusSection(id: "s")
        section.reserve(MockFocusable(id: "r"))
        section.register(MockFocusable(id: "a"))
        #expect(section.holdsReservation)
        section.register(MockFocusable(id: "r"))
        #expect(!section.holdsReservation)
        #expect(ids(section) == ["r", "a"])
    }

    @Test("A filed handler repointed this pass answers to its new id, not its old one")
    func repointedHandlerAnswersToItsNewID() {
        let manager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = manager
        let context = RenderContext(
            availableWidth: 10, availableHeight: 1, environment: environment, tuiContext: TUIContext())
        let handler = Repointable("old")
        FocusRegistration.register(context: context, handler: handler, focusID: "old")

        // The control declares another id later in the same pass: the one
        // handler is re-pointed, and stays the one element in the ring.
        FocusRegistration.register(context: context, handler: handler, focusID: "new")
        #expect(manager.focusableIDs == ["new"])

        // So the new id is taken, and the old one free again.
        manager.register(MockFocusable(id: "new"))
        manager.register(MockFocusable(id: "old"))
        #expect(manager.focusableIDs == ["new", "old"])
    }
}
