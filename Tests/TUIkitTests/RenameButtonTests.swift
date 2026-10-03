//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenameButtonTests.swift
//
//  `RenameButton`, `RenameAction` and `renameAction(_:)`: the button performs
//  the action the environment holds, and is disabled where there is none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Counts renames.
private final class RenameLog: @unchecked Sendable {
    var count = 0
}

@MainActor
@Suite("RenameButton")
struct RenameButtonTests {
    @Test("The button is titled Rename, and performs the environment's action")
    func performsTheAction() {
        let log = RenameLog()
        let harness = InputChainHarness()
        let drawn = harness.frame(RenameButton().renameAction { log.count += 1 })
        #expect(drawn.lines.joined().stripped.contains("Rename"))
        harness.play([KeyEvent(key: .enter)]) { RenameButton().renameAction { log.count += 1 } }
        #expect(log.count == 1)
    }

    @Test("With no action in the environment there is no rename and the button does nothing")
    func disabledWithoutAnAction() {
        let harness = InputChainHarness()
        let consumed = harness.play([KeyEvent(key: .enter)]) { RenameButton() }
        #expect(consumed == [false], "a disabled button is no focus stop to take the key")
    }

    @Test("The environment value reads the action set above it")
    func environmentValue() {
        var seen: RenameAction?
        let log = RenameLog()
        _ = renderToBuffer(
            EnvironmentReader(\.rename) { seen = $0 }.renameAction { log.count += 1 },
            context: makeRenderContext())
        seen?()
        #expect(log.count == 1)
        _ = renderToBuffer(EnvironmentReader(\.rename) { seen = $0 }, context: makeRenderContext())
        #expect(seen == nil)
    }
}

/// Hands `read` the environment value at `keyPath` when it renders.
private struct EnvironmentReader<Value>: View {
    let keyPath: KeyPath<EnvironmentValues, Value>
    let read: (Value) -> Void

    init(_ keyPath: KeyPath<EnvironmentValues, Value>, read: @escaping (Value) -> Void) {
        self.keyPath = keyPath
        self.read = read
    }

    var body: some View {
        _EnvironmentReaderCore(keyPath: keyPath, read: read)
    }
}

private struct _EnvironmentReaderCore<Value>: View, Renderable {
    let keyPath: KeyPath<EnvironmentValues, Value>
    let read: (Value) -> Void
    var body: Never { fatalError("renders via Renderable") }
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        read(context.environment[keyPath: keyPath])
        return FrameBuffer()
    }
}
