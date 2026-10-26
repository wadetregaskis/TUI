//  🖥️ TUI — A Terminal UI framework for Swift
//  EnvironmentSlotNoteTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIView

/// A test-local environment value, so the slots noted here are no one else's.
private struct NotedKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var noted: Int {
        get { self[NotedKey.self] }
        set { self[NotedKey.self] = newValue }
    }
}

/// A value with no `Equatable`, which a slot can only report as incomparable.
private struct Opaque {}

/// `RenderCache.noteAppliedEnvironment` takes its value as an autoclosure, so
/// that the visits that never look at it — a repeat visit within a pass, a slot
/// that has gone incomparable — do not pay to make it: `EnvironmentModifier`'s
/// value is a palette cast and an `Any` box. The answers must be what they
/// were when the value was always made, and the value made exactly where it
/// is used.
@MainActor
@Suite("Noting an applied environment value")
struct EnvironmentSlotNoteTests {

    @Test("The value is made once a pass at most, and the answers are unchanged")
    func valueIsMadeOnlyWhereUsed() {
        let cache = RenderCache()
        let identity = ViewIdentity(path: "Root")
        var made = 0
        func value(_ number: Int) -> Any {
            made += 1
            return number
        }
        func note(_ number: Int) -> RenderCache.EnvironmentChange {
            cache.noteAppliedEnvironment(
                value(number), identity: identity, keyPath: \EnvironmentValues.noted, depth: 0)
        }

        cache.beginRenderPass()
        #expect(note(1) == .first)
        #expect(made == 1)
        // The repeat visits of one pass are answered from the first.
        #expect(note(1) == .unchanged)
        #expect(note(1) == .unchanged)
        #expect(made == 1)

        cache.beginRenderPass()
        #expect(note(1) == .unchanged)
        #expect(made == 2)
        // Already answered this pass: even a different value is not looked at,
        // as before.
        #expect(note(2) == .unchanged)
        #expect(made == 2)

        cache.beginRenderPass()
        #expect(note(3) == .changed)
        #expect(made == 3)
        #expect(note(3) == .unchanged)
        #expect(made == 3)
    }

    @Test("A slot that went incomparable never makes its value again")
    func incomparableSlotSkipsTheValue() {
        let cache = RenderCache()
        let identity = ViewIdentity(path: "Root")
        var made = 0
        func opaque() -> Any {
            made += 1
            return Opaque()
        }
        func note() -> RenderCache.EnvironmentChange {
            cache.noteAppliedEnvironment(opaque(), identity: identity, keyPath: \EnvironmentValues.noted, depth: 0)
        }

        cache.beginRenderPass()
        #expect(note() == .incomparable)
        #expect(made == 1)
        #expect(note() == .incomparable)
        cache.beginRenderPass()
        #expect(note() == .incomparable)
        cache.beginRenderPass()
        #expect(note() == .incomparable)
        #expect(made == 1)
    }
}
