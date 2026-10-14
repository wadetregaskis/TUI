//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRangeTests.swift
//
//  `List(0..<n) { … }`, SwiftUI's list over a range of integers (the semantic
//  audit's item 104), without selection and with each kind of it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("List over a range of integers")
struct ListRangeTests {
    private func rows(_ view: some View) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: 6)).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("A list over a range draws a row for each integer, with or without selection")
    func rangeRows() {
        let plain = rows(List(0..<3) { Text("row \($0)") })
        #expect(plain.contains("row 0") && plain.contains("row 1") && plain.contains("row 2"), "\(plain)")
        let single = rows(List(0..<3, selection: .constant(Int?.some(1))) { Text("row \($0)") })
        #expect(single.contains("row 2"), "\(single)")
        let multiple = rows(List(0..<3, selection: .constant(Set([0, 2]))) { Text("row \($0)") })
        #expect(multiple.contains("row 0"), "\(multiple)")
    }

    /// SwiftUI's selection bindings are optional (the semantic audit's item
    /// 76): `List(selection: isEditing ? $selection : nil)` turns selection
    /// off by passing no binding.
    @Test("A selection binding may be nil, and the list then selects nothing", arguments: [false, true])
    func optionalSelectionBinding(editing: Bool) {
        var single: Int? = 1
        var several: Set<Int> = [0]
        let singleBinding = Binding(get: { single }, set: { single = $0 })
        let severalBinding = Binding(get: { several }, set: { several = $0 })
        let off = rows(List(selection: editing ? singleBinding : nil) { ForEach(0..<3) { Text("row \($0)") } })
        #expect(off.contains("row 2"), "\(off)")
        let offSeveral = rows(List(0..<3, selection: editing ? severalBinding : nil) { Text("row \($0)") })
        #expect(offSeveral.contains("row 0"), "\(offSeveral)")
        let on = rows(List(0..<3, selection: singleBinding) { Text("row \($0)") })
        #expect(on.contains("row 1"), "\(on)")
    }
}
