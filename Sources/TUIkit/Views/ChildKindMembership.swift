//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChildKindMembership.swift
//
//  Whether a kind of child a container treats specially — a `Section` — can be
//  among the children a view hands it, answered from the view's TYPE, so a
//  container whose content can hold none skips the walk that would look.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The Kinds Asked About

/// A kind of child a container treats specially, asked about a view's type
/// before any of its children is resolved (``mayHandOver(_:_:)``).
enum ChildKind {
    /// A `Section`: a lazy grid draws them section by section, a lazy stack
    /// keeps them whole, a menu styles them.
    case section
}

/// A provider that knows from its TYPE whether a kind of child can be among
/// the children it hands its container — see ``mayHandOver(_:_:)``.
@MainActor
protocol ChildKindsKnowing {
    /// Whether an instance of this type can hand its container a child of
    /// `kind`, asking each type it holds once (`visited`).
    static func mayHandOver(_ kind: ChildKind, visited: inout Set<ObjectIdentifier>) -> Bool
}

// MARK: - The Walk

/// Whether a child of `kind` can be among the children a view of type `type`
/// hands the container resolving it: `false` only where the type proves there
/// is none, so a container that treats such a child specially can skip the
/// walk that would look for one, which is every child of its content.
///
/// A view that is no provider is one child, and none of these — unless it is
/// a view of the app's own whose body is taken apart (`compositeMembers`),
/// which hands over what its body does. A `Section` (or a section under
/// modifiers that reach its parts) is a section. The providers whose content
/// is spelled in their type — a tuple, a `Group`, an `if`, a `ForEach`'s row,
/// a modifier on several views — answer for their content. Any other provider
/// — an `AnyView`, the subview and section APIs, one added later — may hand
/// over anything, and is answered `true`: the walk finds out.
///
/// A view type met again on the way down — a tree view whose body loops over
/// rows of its own type — answers `false` the second time: what it can hand
/// over is already being asked of it.
@MainActor
func mayHandOver<V: View>(_ kind: ChildKind, _ type: V.Type) -> Bool {
    var visited: Set<ObjectIdentifier> = []
    return mayHandOver(kind, type, visited: &visited)
}

/// ``mayHandOver(_:_:)``, carrying the types already asked.
@MainActor
func mayHandOver<V: View>(_ kind: ChildKind, _ type: V.Type, visited: inout Set<ObjectIdentifier>) -> Bool {
    switch kind {
    case .section: if type is any SectionPartsProviding.Type { return true }
    }
    guard type is any ChildViewProvider.Type else {
        guard V._handsOverChildren, isCompositeHandingOverChildren(type),
            visited.insert(ObjectIdentifier(type)).inserted
        else { return false }
        return mayHandOver(kind, V.Body.self, visited: &visited)
    }
    if let known = type as? any ChildKindsKnowing.Type {
        guard visited.insert(ObjectIdentifier(type)).inserted else { return false }
        return known.mayHandOver(kind, visited: &visited)
    }
    if let wrapper = type as? any ContentRewrapping.Type {
        return wrappedMayHandOver(kind, wrapper, visited: &visited)
    }
    return true
}

/// Whether a `Section` can be among the children a view of type `type` hands
/// the container resolving it — ``mayHandOver(_:_:)`` of ``ChildKind/section``.
@MainActor
func mayHandOverSections<V: View>(_ type: V.Type) -> Bool {
    mayHandOver(.section, type)
}

/// ``mayHandOver(_:_:visited:)`` of a wrapper's content, the existential
/// opened.
@MainActor
private func wrappedMayHandOver<W: ContentRewrapping>(
    _ kind: ChildKind, _: W.Type, visited: inout Set<ObjectIdentifier>
) -> Bool {
    mayHandOver(kind, W.WrappedContent.self, visited: &visited)
}

// MARK: - The Framework's Own Providers

extension TupleView: ChildKindsKnowing {
    static func mayHandOver(_ kind: ChildKind, visited: inout Set<ObjectIdentifier>) -> Bool {
        var found = false
        func check<T: View>(_: T.Type) {
            if !found, TUIkit.mayHandOver(kind, T.self, visited: &visited) { found = true }
        }
        repeat check((each V).self)
        return found
    }
}

extension ConditionalView: ChildKindsKnowing {
    static func mayHandOver(_ kind: ChildKind, visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOver(kind, TrueContent.self, visited: &visited)
            || TUIkit.mayHandOver(kind, FalseContent.self, visited: &visited)
    }
}

extension Optional: ChildKindsKnowing where Wrapped: View {
    static func mayHandOver(_ kind: ChildKind, visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOver(kind, Wrapped.self, visited: &visited)
    }
}

extension ModifiedView: ChildKindsKnowing where Content: ChildViewProvider {
    static func mayHandOver(_ kind: ChildKind, visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOver(kind, Content.self, visited: &visited)
    }
}

extension Group: ChildKindsKnowing where Content: View {
    static func mayHandOver(_ kind: ChildKind, visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOver(kind, Content.self, visited: &visited)
    }
}

/// A loop's rows are its children, so its row type answers.
extension ForEach: ChildKindsKnowing where Content: View {
    static func mayHandOver(_ kind: ChildKind, visited: inout Set<ObjectIdentifier>) -> Bool {
        TUIkit.mayHandOver(kind, Content.self, visited: &visited)
    }
}
