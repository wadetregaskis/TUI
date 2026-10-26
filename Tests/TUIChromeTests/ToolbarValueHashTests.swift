//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarValueHashTests.swift
//
//  A view that declares toolbar items, or states something about the bars,
//  keeps its value hash: the placements and statements it holds are read by
//  their cases, so the memos keyed by the hash still serve the view and every
//  container holding it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIChrome
@testable import TUIFoundation
@testable import TUIView

@MainActor
@Suite("Toolbar values in the value hash")
struct ToolbarValueHashTests {
    private let plans = ValueHashPlans()

    private func hash<V>(_ value: V) -> Int? {
        withUnsafePointer(to: value) { plans.valueHash(at: $0) }
    }

    private func expectHashed(_ type: Any.Type, sourceLocation: SourceLocation = #_sourceLocation) {
        let plan = plans.plan(for: type).pointee
        #expect(plan.shape != .bypass, "\(type): \(plan.bypassReason ?? "")", sourceLocation: sourceLocation)
    }

    @Test("Every item placement is read by the value hash, an accessory bar's too")
    func itemPlacements() {
        expectHashed(ToolbarItemPlacement.self)
        let placements: [ToolbarItemPlacement] = [
            .automatic, .principal, .navigation, .primaryAction, .secondaryAction, .status, .confirmationAction,
            .cancellationAction, .destructiveAction, .bottomBar, .topBarLeading, .topBarTrailing, .keyboard,
            .accessoryBar(id: "a"), .accessoryBar(id: "b"), .accessoryBar(id: 1),
        ]
        let hashes = placements.map { hash($0) }
        #expect(!hashes.contains(nil), "\(hashes)")
        #expect(Set(hashes).count == placements.count, "\(hashes)")
        #expect(hash(ToolbarItemPlacement.accessoryBar(id: "a")) == hashes[13])
    }

    @Test("Every bar placement is read by the value hash, an accessory bar's too")
    func barPlacements() {
        expectHashed(ToolbarPlacement.self)
        let placements: [ToolbarPlacement] = [
            .automatic, .windowToolbar, .bottomBar, .accessoryBar(id: "a"), .accessoryBar(id: "b"),
        ]
        let hashes = placements.map { hash($0) }
        #expect(!hashes.contains(nil), "\(hashes)")
        #expect(Set(hashes).count == placements.count, "\(hashes)")
        #expect(hash(ToolbarPlacement.accessoryBar(id: "a")) == hashes[3])
    }

    @Test("A view declaring toolbar items keeps its value hash, whatever their placements")
    func toolbarDeclarations() {
        // `.toolbar { views }`: a group at the automatic placement.
        expectHashed(type(of: Text("a").toolbar { Text("v") }))
        expectHashed(
            type(of: Text("a").toolbar { ToolbarItemGroup(placement: .accessoryBar(id: "bar")) { Text("i") } }))
        expectHashed(
            type(
                of: Text("a").toolbar {
                    ToolbarItemGroup(placement: .primaryAction) { Text("g") } label: { Text("l") }
                }))
        expectHashed(type(of: Text("a").toolbar { ToolbarSpacer(placement: .accessoryBar(id: "bar")) }))
        // A container holding one keeps its hash too.
        expectHashed(
            type(
                of: VStack {
                    Text("a").toolbar { ToolbarItemGroup(placement: .keyboard) { Text("k") } }
                    Text("b")
                }))
        expectHashed(
            type(of: Text("a").toolbar(id: "t") { ToolbarItem(id: "x", placement: .accessoryBar(id: 1)) { Text("x") } })
        )
    }

    @Test("A view stating something about the bars keeps its value hash")
    func barStatements() {
        expectHashed(type(of: Text("a").toolbarVisibility(.hidden, for: .accessoryBar(id: "bar"))))
        expectHashed(type(of: Text("a").toolbarBackground(.red, for: .bottomBar)))
        expectHashed(type(of: Text("a").toolbarBackgroundVisibility(.hidden, for: .windowToolbar)))
        expectHashed(type(of: Text("a").toolbarRole(.editor)))
        let views = [
            AnyView(Text("a").toolbarVisibility(.hidden, for: .bottomBar)),
            AnyView(Text("a").toolbarVisibility(.visible, for: .bottomBar)),
            AnyView(Text("a").toolbarBackground(.red, for: .bottomBar)),
            AnyView(Text("a").toolbarBackground(.blue, for: .bottomBar)),
            AnyView(Text("a").toolbarBackgroundVisibility(.hidden, for: .bottomBar)),
            AnyView(Text("a").toolbarRole(.editor)),
            AnyView(Text("a").toolbarRole(.automatic)),
        ]
        let hashes = views.map { hash($0) }
        #expect(!hashes.contains(nil), "\(hashes)")
        #expect(Set(hashes).count == views.count, "\(hashes)")
    }
}
