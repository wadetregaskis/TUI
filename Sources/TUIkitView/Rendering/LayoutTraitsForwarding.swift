//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LayoutTraitsForwarding.swift
//
//  A view that stands in for a child some other container has already
//  resolved — a `Subview` — lays out with that child's traits, not its own
//  type's.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A view that stands in for a child resolved somewhere else, and so is, to
/// the container laying it out, whatever that child is: a spacer if it is a
/// `Spacer`, at its z-index, with its alignment guides.
///
/// `Subview` is the conformer. Its TYPE is the same for every member it can
/// stand for, so the static witnesses ``View/_isSpacer``,
/// ``View/_providesZIndex`` and ``View/_providesAlignmentGuide`` can only say
/// that it MAY be a spacer or carry the others; ``ChildView`` then asks the
/// instance, here, when it is built — once, into the fields it stores. So a
/// stack reading those fields on every frame costs what it always did, and a
/// child that is no proxy never reaches the cast that finds one: its witnesses
/// are `false`.
///
/// What SwiftUI does, measured on macOS 15.8: a `Spacer` placed through
/// `ForEach(subviews:)` is a spacer (its minimum length and its fill), an
/// `.alignmentGuide` on a member moves the proxy, `.zIndex` orders it in a
/// `ZStack`, and a `.layoutValue` reaches the `Layout` it is placed in.
@MainActor
package protocol LayoutTraitsForwarding {
    /// The child this view stands in for, as the container that resolved it
    /// made it.
    var forwardedChild: ChildView { get }
}
