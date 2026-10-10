//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionIsExpandedTests.swift
//
//  `Section(_:isExpanded:content:)` and `Section(isExpanded:content:header:)`:
//  the header behind a disclosure triangle, the content shown only while the
//  binding is true — in a list, where a collapsed section's rows leave it, and
//  outside one — and the header a control the keyboard toggles.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Section isExpanded")
struct SectionIsExpandedTests {
    private final class Box {
        var expanded: Bool
        init(_ expanded: Bool) { self.expanded = expanded }
        var binding: Binding<Bool> { Binding(get: { self.expanded }, set: { self.expanded = $0 }) }
    }

    private func lines(_ view: some View, context: RenderContext? = nil) -> [String] {
        renderToBuffer(view, context: context ?? makeRenderContext(width: 30, height: 10)).lines.map(\.stripped)
    }

    private func list(_ box: Box) -> some View {
        List {
            Text("Loose")
            Section("Fruit", isExpanded: box.binding) {
                Text("Apple")
                Text("Pear")
            }
            Section("Veg") {
                Text("Leek")
            }
        }
    }

    @Test("In a list, a collapsed section's rows leave it and its header keeps a closed triangle")
    func collapsedInAList() {
        let open = lines(list(Box(true)))
        #expect(open.contains { $0.contains("▼") && $0.contains("Fruit") }, "\(open)")
        #expect(open.contains { $0.contains("Apple") } && open.contains { $0.contains("Pear") }, "\(open)")
        let closed = lines(list(Box(false)))
        #expect(closed.contains { $0.contains("▶") && $0.contains("Fruit") }, "\(closed)")
        #expect(!closed.contains { $0.contains("Apple") || $0.contains("Pear") }, "\(closed)")
        #expect(closed.contains { $0.contains("Leek") } && closed.contains { $0.contains("Loose") }, "\(closed)")
    }

    @Test("Outside a list the section draws its header as written and its content only while expanded")
    func collapsedOutsideAList() {
        func view(_ box: Box) -> some View {
            VStack {
                Section(isExpanded: box.binding) {
                    Text("Inside")
                } header: {
                    Text("Head")
                }
            }
        }
        let open = lines(view(Box(true)))
        #expect(open.contains { $0.contains("Head") } && open.contains { $0.contains("Inside") }, "\(open)")
        let closed = lines(view(Box(false)))
        #expect(closed.contains { $0.contains("Head") } && !closed.contains { $0.contains("Inside") }, "\(closed)")
        // No disclosure triangle: SwiftUI's header outside a list is no
        // control (measured on macOS 15.8), so neither is this one.
        #expect(!(open + closed).contains { $0.contains("▶") || $0.contains("▼") }, "\(open) \(closed)")
    }

    @Test("The header is a focus stop that Return toggles")
    func headerTogglesFromTheKeyboard() {
        let box = Box(false)
        let context = makeRenderContext(width: 30, height: 10)
        let view = list(box)
        _ = lines(view, context: context)
        guard let manager = context.environment.focusManager else {
            Issue.record("no focus manager")
            return
        }
        let ring = manager.registeredFocusIDsInActiveSection()
        guard let disclosure = ring.first(where: { !$0.hasPrefix("list") }) else {
            Issue.record("the header is no focus stop: \(ring)")
            return
        }
        manager.focus(id: disclosure)
        _ = lines(view, context: context)
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .enter)))
        #expect(box.expanded, "Return opened the section")
        let open = lines(view, context: context)
        #expect(open.contains { $0.contains("Apple") }, "\(open)")
    }

    @Test("A section built without a binding has no triangle")
    func plainSectionHasNoTriangle() {
        let drawn = lines(List { Section("Veg") { Text("Leek") } })
        #expect(!drawn.contains { $0.contains("▶") || $0.contains("▼") }, "\(drawn)")
    }
}
