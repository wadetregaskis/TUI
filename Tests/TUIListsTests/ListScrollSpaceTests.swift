//  🖥️ TUI — A Terminal UI framework for Swift
//  ListScrollSpaceTests.swift
//
//  A `List` owns `.scrollView` for its rows (decisions B-D5G-9): SwiftUI's
//  list is itself the scroll view its rows are in, so a reader in a row asking
//  `.scrollView` is answered in the list's content window — not by a scroll
//  view around the list, nor, with none, in the global space.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport

@MainActor
private final class Seen {
    var frame: CellRect?
    var bounds: CellRect??
}

@MainActor
private func reader(_ seen: Seen, in space: some CoordinateSpaceProtocol) -> some View {
    GeometryReader { proxy in
        // swiftlint:disable:next redundant_discardable_let
        let _ = {
            seen.frame = proxy.frame(in: space)
            seen.bounds = .some(proxy.bounds(of: .scrollView))
        }()
        Text("R")
    }
    .frame(width: 4, height: 1)
}

@MainActor
@Suite("A List owns .scrollView for its rows")
struct ListScrollSpaceTests {
    /// Two lines above a plain list six lines tall whose fourth row reads
    /// where it is.
    private func page(_ seen: Seen, in space: some CoordinateSpaceProtocol) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("above")
            Text("above")
            List(selection: .constant(Int?.none)) {
                ForEach(0..<3, id: \.self) { Text("row \($0)") }
                reader(seen, in: space)
                ForEach(4..<30, id: \.self) { Text("row \($0)") }
            }
            .listStyle(.plain)
            .frame(height: 6)
        }
    }

    @Test("A reader in a row is answered in the list's content window, and moves through it as the list scrolls")
    func readerInARow() {
        let seen = Seen()
        let harness = InputChainHarness()
        harness.frame(page(seen, in: .scrollView))
        #expect(seen.frame?.y == 3, "the fourth row of the window: \(String(describing: seen.frame))")
        #expect(seen.bounds??.height == 6, "the window is six lines tall: \(String(describing: seen.bounds))")
        (harness.focusManager.currentFocused as? ItemListHandler<Int>)?.scrollToOffset(2)
        harness.frame(page(seen, in: .scrollView))
        #expect(seen.frame?.y == 1, "two rows scrolled away: \(String(describing: seen.frame))")
    }

    @Test("The vertical axis's scroll view is the list's too; the horizontal one is not")
    func axes() {
        let vertical = Seen()
        let harness = InputChainHarness()
        harness.frame(page(vertical, in: .scrollView(axis: .vertical)))
        #expect(vertical.frame?.y == 3, "\(String(describing: vertical.frame))")
        let horizontal = Seen()
        let other = InputChainHarness()
        other.frame(page(horizontal, in: .scrollView(axis: .horizontal)))
        // No scroll view scrolls sideways: the global space.
        #expect(horizontal.frame?.y == 5, "\(String(describing: horizontal.frame))")
    }
}
