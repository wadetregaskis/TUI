//  🖥️ TUI — A Terminal UI framework for Swift
//  DispatchedObjectEnvironmentTests.swift
//
//  An `@Environment` in a class property several views hold, read by a
//  closure dispatched from inside one of them, reads that holder's
//  environment (decisions B-DYNVFIX-3, option (c)): a Button's action in the
//  second holder sees the second's, clicked or pressed from the keyboard.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

private struct Tint: EnvironmentKey {
    static let defaultValue = "none"
}

extension EnvironmentValues {
    fileprivate var dispatchTint: String {
        get { self[Tint.self] }
        set { self[Tint.self] = newValue }
    }
}

/// A class app property holding an `@Environment`.
private final class Tinted: DynamicProperty {
    @Environment(\.dispatchTint) var tint
}

private final class Log: @unchecked Sendable {
    var read: [String] = []
}

/// A holder of the object: a button whose action reads the object's tint.
private struct Holder: View {
    let name: String
    let object: Tinted
    let log: Log

    var body: some View {
        let object = object
        let log = log
        return Button(name) { log.read.append("\(name) \(object.tint)") }
    }
}

private struct Shared {
    let object: Tinted
}

/// Two holders of one object under two tints, one above the other.
private struct Page: View {
    let shared: Shared
    let log: Log

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Holder(name: "first", object: shared.object, log: log).environment(\.dispatchTint, "red")
            Holder(name: "second", object: shared.object, log: log).environment(\.dispatchTint, "blue")
        }
    }
}

@MainActor
@Suite("An object's environment, read from a dispatch")
struct DispatchedObjectEnvironmentTests {
    @Test("A click on the second holder's button reads the second holder's environment")
    func clickReadsItsHolders() {
        let log = Log()
        let shared = Shared(object: Tinted())
        let harness = InputChainHarness()
        let view = { Page(shared: shared, log: log) }
        harness.frame(view())
        harness.click(1, 1, view)
        harness.click(1, 0, view)
        #expect(log.read == ["second blue", "first red"])
    }

    @Test("Return on the focused second holder's button reads the second holder's environment")
    func keyReadsTheFocusedHolders() {
        let log = Log()
        let shared = Shared(object: Tinted())
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .tab), KeyEvent(key: .enter)]) { Page(shared: shared, log: log) }
        #expect(log.read == ["second blue"])
    }

    @Test("Outside a dispatch the object reads its first holder's environment, as before")
    func atRestReadsThePrimarys() {
        let log = Log()
        let shared = Shared(object: Tinted())
        let harness = InputChainHarness()
        harness.frame(Page(shared: shared, log: log))
        #expect(shared.object.tint == "red")
    }
}
