//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ForEachRowMembers.swift
//
//  A `ForEach` row of several views hands its container each of them, as
//  SwiftUI's does: `ForEach(0..<2) { _ in Group { a; b } }` is four children of
//  the stack it is in, four subviews of a `Layout`, four rows of a list.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The Shape of a Loop's Rows

/// How a loop's rows map onto its container's children.
enum ForEachRowShape: Equatable {
    /// One child per element: the row as it is — every row type that is not a
    /// provider of several views, which is nearly every row.
    case single
    /// No children at all: every row is an `EmptyView`.
    case none
    /// The same number of children from every element, known from the row's
    /// type — `Group { a; b }`, a row of two views — so a child's ordinal maps
    /// to its element by arithmetic.
    case fixed(Int)
    /// A number that depends on each row — a loop in the row, an `if` whose
    /// arms differ, an `if` without `else` among several views, a section —
    /// so each row is built and counted.
    case varying

    /// How many children each element makes, when every element makes as
    /// many.
    var childrenPerElement: Int? {
        switch self {
        case .single: 1
        case .none: 0
        case .fixed(let count): count
        case .varying: nil
        }
    }
}

extension ForEach where Content: View {
    /// The shape of this loop's rows, from the row type alone.
    ///
    /// A row type that is no provider of children — a `Text`, a stack, a view
    /// of the app's own whose body is one view — is answered by one cached
    /// conformance test, and its rows take the path they always took: the
    /// loop's hot path is untouched for everything but rows of several views.
    ///
    /// - Parameter sectionWholeness: Which sections the walk keeps whole
    ///   (`RenderContext.sectionWholeness`). One that keeps a loop's section
    ///   rows whole has a row that is a section be one child, as it always
    ///   was in a `List` — and so is a row of the app's own whose body is one
    ///   (``isSectionRowType(_:)``): drawn whole where the walk keeps only a
    ///   loop's sections whole (an unpinned lazy stack, whose section finds
    ///   it is the stack's own by where it draws), and handed over as the
    ///   section its body is where the walk keeps every section whole (a
    ///   `List`, the section APIs, a pinned lazy stack, which look for the
    ///   section among their children) — one child an element either way, so
    ///   a lazy stack builds only the sections it draws.
    func rowShape(sectionWholeness: SectionWholeness) -> ForEachRowShape {
        // A row of the app's own type is taken apart only when its body hands
        // over children (decisions D1S, B-D1S-6) — the static witness, a few
        // calls down its body types, and no cast for a body of one view.
        guard Content.self is any ChildViewProvider.Type || Content.self == EmptyView.self
            || (Content._handsOverChildren && isCompositeHandingOverChildren(Content.self))
        else { return .single }
        if sectionWholeness != .apart {
            if Content.self is any SectionPartsProviding.Type { return .single }
            if isSectionRowType(Content.self) { return sectionWholeness == .all ? .fixed(1) : .single }
        }
        switch staticRowMemberCount(Content.self) {
        case 1: return .single
        case 0: return .none
        case let count?: return .fixed(count)
        case nil: return .varying
        }
    }

    /// The children `element`'s row hands its container: its members, each
    /// pinned under the identity the row takes as one child, and keyed by the
    /// element (``ChildView/keyedAsMember(ofRowKeyed:)``), so a seek for the
    /// element finds the row's first, and the row's `@State` follows the
    /// element as a one-view row's does. A row that stays whole here — a
    /// section, in a walk that keeps them — is the one child it always was.
    ///
    /// An `EmptyView` among them is none, as SwiftUI counts it.
    func rowMembers(of element: Data.Element, context: RenderContext) -> [ChildView] {
        let key = identityKey(elementID(of: element))
        let rowScope = context.withChildIdentity(erasedType: Content.self, key: key)
        let row = content(element)
        if let provider = row as? ChildViewProvider, provider.staysWhole(in: rowScope) {
            return [makeChild(for: element)]
        }
        return resolveChildViews(from: row, context: rowScope).compactMap { member in
            guard !isEmptyMember(member) else { return nil }
            return member.pinningIdentity(to: rowScope.identity).keyedAsMember(ofRowKeyed: key)
        }
    }

    /// Every element's members, in order, with the element offset each came
    /// from — the eager form of a loop whose rows vary.
    func allRowMembers(
        of data: Data, context: RenderContext
    ) -> (members: [ChildView], elementOffsets: [Int]) {
        var members: [ChildView] = []
        var elementOffsets: [Int] = []
        for (offset, element) in data.enumerated() {
            let row = rowMembers(of: element, context: context)
            members += row
            elementOffsets += repeatElement(offset, count: row.count)
        }
        return (members, elementOffsets)
    }

    /// The member at `index` of `element`'s row — of a loop whose rows make
    /// the same number of children each (``ForEachRowShape/fixed(_:)``).
    ///
    /// Only a type whose every instance makes that number is counted fixed
    /// (``staticMemberCount(_:)``), so the row has the member; the empty one
    /// below is a guard, never a row of the container — if a count and a
    /// row ever disagree, a blank child is drawn rather than a trap hit.
    func rowMember(_ index: Int, of element: Data.Element, context: RenderContext) -> ChildView {
        let members = rowMembers(of: element, context: context)
        if index < members.count { return members[index] }
        let key = identityKey(elementID(of: element))
        let rowScope = context.withChildIdentity(erasedType: Content.self, key: key)
        return ChildView(EmptyView(), childIndex: index)
            .pinningIdentity(to: rowScope.identity).keyedAsMember(ofRowKeyed: key)
    }
}

// MARK: - A Section of the App's Own

/// Whether `type` is a view of the app's own whose body is a section — through
/// any number of such views, and under modifiers that reach the section's
/// parts — so that a loop of them is a loop of sections
/// (``ForEach/rowShape(sectionWholeness:)``).
///
/// From the types alone: no body is evaluated to answer.
@MainActor
func isSectionRowType<V: View>(_ type: V.Type) -> Bool {
    var depth = 0
    return isSectionRowType(type, depth: &depth)
}

/// ``isSectionRowType(_:)``, a body deeper each step, and `false` past a depth
/// no written view nests its bodies to.
@MainActor
private func isSectionRowType<V: View>(_ type: V.Type, depth: inout Int) -> Bool {
    guard isCompositeHandingOverChildren(type), depth < 32 else { return false }
    if V.Body.self is any SectionPartsProviding.Type { return true }
    depth += 1
    return isSectionRowType(V.Body.self, depth: &depth)
}
