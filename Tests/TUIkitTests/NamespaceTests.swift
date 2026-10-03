//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NamespaceTests.swift
//
//  `@Namespace`: an id that belongs to the view holding it, the same on every
//  frame and never shared with another property.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// A reference cell a view body writes what it read into.
private final class Seen {
    var ids: [Namespace.ID] = []
}

@MainActor
@Suite("@Namespace")
struct NamespaceTests {
    private struct Holder: View {
        @Namespace var first
        @Namespace var second
        let seen: Seen

        var body: some View {
            seen.ids.append(contentsOf: [first, second])
            return Text("x")
        }
    }

    private func render(_ view: some View, tui: TUIContext) {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 4, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
    }

    @Test("A namespace keeps its id from frame to frame, even when the view value is rebuilt")
    func stableAcrossFrames() {
        let tui = TUIContext()
        let seen = Seen()
        render(Holder(seen: seen), tui: tui)
        render(Holder(seen: seen), tui: tui)
        #expect(seen.ids.count == 4)
        #expect(seen.ids[0] == seen.ids[2], "the first property's id survives a new view value")
        #expect(seen.ids[1] == seen.ids[3], "so does the second's")
    }

    @Test("Two namespaces on one view, and the same namespace on two views, differ")
    func distinct() {
        let tui = TUIContext()
        let seen = Seen()
        // The stack measures each holder before it draws it, so each body runs
        // more than once; what matters is how many DIFFERENT ids they read.
        render(HStack { Holder(seen: seen); Holder(seen: seen) }, tui: tui)
        #expect(Set(seen.ids).count == 4, "every property at every place in the tree has its own id")
    }

    @Test("Read before it renders, a namespace is unique to its property value and is no bound id")
    func unbound() {
        let lhs = Namespace()
        let rhs = Namespace()
        let firstRead = lhs.wrappedValue
        #expect(lhs.wrappedValue == firstRead, "an unbound id still reads the same twice")
        #expect(lhs.wrappedValue != rhs.wrappedValue)
        lhs.bindRenderIdentity(path: "root", propertyIndex: 0)
        rhs.bindRenderIdentity(path: "root", propertyIndex: 0)
        #expect(lhs.wrappedValue == rhs.wrappedValue, "bound at the same place, the ids agree")
    }
}
