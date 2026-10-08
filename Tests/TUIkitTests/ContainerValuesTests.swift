//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerValuesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

// MARK: - Fixtures

private struct PinKey: ContainerValueKey {
    static let defaultValue = -1
}

private struct PinPosition: Equatable {
    var rotation = 0
    var xOffset = 0
}

private struct PinPositionKey: ContainerValueKey {
    static let defaultValue = PinPosition()
}

private struct LabelKey: ContainerValueKey {
    static let defaultValue: String? = "unset"
}

extension ContainerValues {
    fileprivate var pin: Int {
        get { self[PinKey.self] }
        set { self[PinKey.self] = newValue }
    }

    fileprivate var pinPosition: PinPosition {
        get { self[PinPositionKey.self] }
        set { self[PinPositionKey.self] = newValue }
    }

    fileprivate var label: String? {
        get { self[LabelKey.self] }
        set { self[LabelKey.self] = newValue }
    }
}

/// What a layout read off its subviews, in subview order.
@MainActor
private final class Seen {
    var values: [ContainerValues] = []
}

/// Records every subview's container values, and draws nothing.
private struct Reads: Layout {
    let seen: Seen

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        seen.values = subviews.map(\.containerValues)
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {}
}

/// An element that compares equal by value, so a loop over it memoises its
/// rows (`ForEach.makeChild`).
private struct Item: Identifiable, Equatable {
    let id: Int
}

// MARK: - Suite

/// Container values as SwiftUI measures them: written on a view, read by the
/// container closest around it through the modifiers between, and by nothing
/// further out.
@MainActor
@Suite("Container values")
struct ContainerValuesTests {

    private func values(@ViewBuilder _ content: () -> some View) -> [ContainerValues] {
        let seen = Seen()
        let layout = Reads(seen: seen)
        _ = renderToBuffer(layout { content() }, context: makeRenderContext(width: 40, height: 10))
        return seen.values
    }

    @Test("A value written on a subview reaches the container around it")
    func valueReachesContainer() {
        let read = values {
            Text("A").containerValue(\.pin, 1)
            Text("B").containerValue(\.pin, 2)
            Text("C")
        }
        #expect(read.map(\.pin) == [1, 2, -1])
    }

    @Test("A value survives a modifier that is not a container")
    func valueSurvivesModifiers() {
        let read = values {
            Text("C").containerValue(\.pin, 3).padding().foregroundStyle(.red)
        }
        #expect(read.map(\.pin) == [3])
    }

    @Test("A value does not escape a container, even one with one child")
    func valueDoesNotEscape() {
        let read = values {
            VStack { Text("A").containerValue(\.pin, 9) }
        }
        #expect(read.map(\.pin) == [-1])
    }

    @Test("A value on a Group reaches each member")
    func valueDistributesOverGroup() {
        let read = values {
            Group {
                Text("a")
                Text("b")
            }
            .containerValue(\.pin, 7)
        }
        #expect(read.map(\.pin) == [7, 7])
    }

    @Test("A value on a ForEach reaches each row")
    func valueDistributesOverForEach() {
        let read = values {
            ForEach(0..<2) { Text("\($0)") }.containerValue(\.pin, 8)
        }
        #expect(read.map(\.pin) == [8, 8])
    }

    @Test("The outermost write of a key wins")
    func outermostWins() {
        let read = values {
            Text("A").containerValue(\.pin, 1).containerValue(\.pin, 2)
        }
        #expect(read.map(\.pin) == [2])
    }

    @Test("Writes to two parts of one value both land")
    func keyPathIntoAValue() {
        let read = values {
            Text("A").containerValue(\.pinPosition.xOffset, 3)
            Text("B")
                .containerValue(\.pinPosition.rotation, 10)
                .containerValue(\.pinPosition.xOffset, 5)
        }
        #expect(
            read.map(\.pinPosition) == [
                PinPosition(rotation: 0, xOffset: 3), PinPosition(rotation: 10, xOffset: 5),
            ])
    }

    @Test("A key never written reads its default, and an optional value written nil reads nil")
    func defaultsAndOptionalNil() {
        let read = values {
            Text("A")
            Text("B").containerValue(\.label, nil)
        }
        #expect(read.map(\.label) == ["unset", nil])
    }

    // MARK: - Tags

    @Test("A tag is a container value, read through a modifier")
    func tagThroughPadding() {
        let read = values {
            Text("a").tag(5).padding()
            Text("b")
        }
        #expect(read.map { $0.tag(for: Int.self) } == [5, nil])
        #expect(read[0].hasTag(5))
        #expect(!read[0].hasTag(6))
        #expect(!read[1].hasTag(5))
    }

    @Test("A tag answers for its own type, and for its optional unless told not to")
    func tagTypes() {
        let read = values {
            Text("a").tag(5)
            Text("b").tag(5, includeOptional: false)
        }
        #expect(read[0].tag(for: String.self) == nil)
        #expect(read[0].tag(for: Int?.self) == .some(5))
        #expect(read[1].tag(for: Int?.self) == nil)
        #expect(read[1].tag(for: Int.self) == 5)
    }

    @Test("A ForEach row is tagged with its element's id, alone or among other views")
    func forEachRowsAreTaggedByID() {
        let alone = values {
            ForEach([10, 20], id: \.self) { Text("\($0)") }
        }
        #expect(alone.map { $0.tag(for: Int.self) } == [10, 20])

        let mixed = values {
            Text("x")
            ForEach(["p", "q"], id: \.self) { Text($0) }
            ForEach(0..<2) { Text("\($0)") }
        }
        #expect(mixed.map { $0.tag(for: String.self) } == [nil, "p", "q", nil, nil])
        #expect(mixed.map { $0.tag(for: Int.self) } == [nil, nil, nil, 0, 1])
    }

    @Test("A row's own tag outranks the one its element's id gives it")
    func explicitTagBeatsImplicit() {
        let read = values {
            ForEach(0..<2) { Text("\($0)").tag($0 + 100) }
        }
        #expect(read.map { $0.tag(for: Int.self) } == [100, 101])
    }

    @Test("A memoised ForEach row's values are read through the memo")
    func memoisedRows() {
        // Equatable elements: each row arrives as `_MemoizedRow`, which is
        // opaque — its values are only reachable through the memo's content.
        let items = (0..<16).map(Item.init)
        let read = values {
            ForEach(items) { item in
                Text("\(item.id)").containerValue(\.pin, item.id * 2)
            }
        }
        #expect(read.map(\.pin) == items.map { $0.id * 2 })
        #expect(read.map { $0.tag(for: Int.self) } == items.map(\.id))
    }
}
