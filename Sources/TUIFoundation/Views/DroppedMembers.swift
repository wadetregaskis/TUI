//  🖥️ TUI — A Terminal UI framework for Swift
//  DroppedMembers.swift
//
//  The one rule for a container that reads its content's members and leaves
//  out one SwiftUI would show: say so, loudly in a debug build. The semantic
//  audit's root cause 5 (owner ruling RC5, 2026-10-23).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// What a container does with a member of its content it does not show though
/// SwiftUI shows it there: a ``SoftTrap`` — a debug build stops at it, a
/// release build reports it once and draws without the member.
///
/// The containers that read their content's members through the shared member
/// resolution (``subviewGroups(of:in:)``) — a `Picker`'s options, an alert's
/// and a confirmation dialog's actions — sort each member by what it is, and a
/// member that answers to nothing they show is left out. Most of those are left
/// out deliberately, as SwiftUI leaves them out; the rest are gaps, which until
/// now went silently (the semantic audit's root cause 5). Each container calls
/// here only for a member SwiftUI would show, as measured (`Tools/SwiftUIProbes/
/// Dropped members (RC5)/`, macOS 15.8):
///
/// | Container | Reported: SwiftUI shows it | Left out quietly: SwiftUI leaves it out too |
/// |---|---|---|
/// | `Picker` | every member with no tag of the selection's type — untagged, tagged with another type, a toggle, a button: each an item of its menu | a `Divider` (a rule), an `EmptyView` (no member) |
/// | `alert`, `confirmationDialog` (measured on an alert) | a text field, a secure field, a toggle (``AlertActionControl``) | anything else that is not a button: a `Text`, an `Image` |
///
/// The four containers that still sort children by their type — a `List`'s
/// rows and sections, a `Grid`'s rows, a `Form`'s rows — leave nothing out:
/// what they do not recognise is a row of its own (`ReflectingContainerSweepTests`).
@MainActor
package enum DroppedMember {
    /// Where ``report(_:leftOutBy:because:)`` sends a report instead of
    /// ``SoftTrap``, while a task binds it — the test seam, as
    /// `ANSIRenderer.translucentReporter` is one: a debug build stops at the
    /// soft trap's assertion, so a test could not otherwise take the path.
    @TaskLocal package static var reporter: (@Sendable (String) -> Void)?

    /// Reports that `container` leaves out `member`, which SwiftUI shows there.
    ///
    /// - Parameters:
    ///   - member: The member left out, as the container met it: its type is
    ///     named in the report.
    ///   - container: The API whose content held it, as an app spells it.
    ///   - reason: Why the container cannot show it, and what to write
    ///     instead, in words an app developer can act on.
    package static func report(_ member: any View, leftOutBy container: String, because reason: String) {
        let message =
            "\(container) leaves out a \(type(of: member)) among its content, which SwiftUI shows: \(reason)"
        if let reporter {
            reporter(message)
        } else {
            SoftTrap.report(message)
        }
    }
}

/// A control SwiftUI's alert and confirmation dialog show among their actions
/// besides a button — a text field, a secure field and a toggle (measured,
/// macOS 15.8, `Tools/SwiftUIProbes/Dropped members (RC5)/`) — which TUI's
/// dialog does not: one is reported as left out (``DroppedMember``), where any
/// other view that is not a button is left out quietly, as SwiftUI leaves it.
@MainActor
package protocol AlertActionControl {}

@MainActor extension Toggle: AlertActionControl {}
