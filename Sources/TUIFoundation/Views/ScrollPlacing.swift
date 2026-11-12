//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPlacing.swift
//
//  The containers SCROLL-FIT's pull passes through (design B-SCROLLFIT-12):
//  each hands a scroll view's request on to the child it leads to, in that
//  child's lines, and places what the child draws in its own.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A container that places its children against a scroll view's request,
/// handing the request on to the children that are pulled (SCROLL-FIT design
/// B-SCROLLFIT-12): a column outward from an anchor (`_VStackCore`,
/// `StackPulledColumn.swift`), and the containers the later lanes make pull.
///
/// A marker, read by type from the identity chain: a lazy stack is pulled only
/// where every container that holds it among siblings conforms
/// (`_VStackCore.isPulledWhereItStands(context:)`), which its measure knows
/// before any request arrives; below any other it is drawn whole
/// (B-SCROLLFIT-13). Nothing is asked of a conformer through it — each shape
/// (column, parallel, forward) reads and answers the request in its own
/// render — so it neither refines `LayoutPlacing` nor asks for a method:
/// a container that pulls need not be one a placement query can walk.
/// Package-wide, for the containers outside this module (`TabView`,
/// `NavigationStack`).
@MainActor
package protocol ScrollPlacing {}
