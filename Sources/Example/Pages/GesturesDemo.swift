//  🖥️ TUI — A Terminal UI framework for Swift
//  GesturesDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Gestures as values: a double click (`TapGesture(count: 2)`), a press held
/// (`.onLongPressGesture`, which also reports the pressing as it happens), a
/// click that knows where it landed (`SpatialTapGesture`), and two gestures
/// composed — a double click that, when it is not one, is a single
/// (`.exclusively(before:)`). Then a parent's tap against its child's: by
/// default the child's wins; `.highPriorityGesture` gives it to the parent,
/// and `.simultaneousGesture` to both.
struct GesturesDemo: View {
    @State private var doubleClicks = 0
    @State private var longPresses = 0
    @State private var isPressing = false
    @State private var spot = "—"
    @State private var composed = "—"

    var body: some View {
        DemoSection("page.mouse.gestures") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.mouse.gesturesExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 2) {
                    tile("page.mouse.gestures.double", "\(doubleClicks)")
                        .gesture(TapGesture(count: 2).onEnded { doubleClicks += 1 })
                    tile("page.mouse.gestures.hold", isPressing ? "…" : "\(longPresses)")
                        .onLongPressGesture(minimumDuration: 0.6) {
                            longPresses += 1
                        } onPressingChanged: { pressing in
                            isPressing = pressing
                        }
                    tile("page.mouse.gestures.where", spot)
                        .gesture(SpatialTapGesture().onEnded { tap in
                            spot = "(\(tap.location.x), \(tap.location.y))"
                        })
                    tile("page.mouse.gestures.either", composed)
                        .gesture(
                            TapGesture(count: 2).onEnded { composed = L("page.mouse.gestures.wasDouble") }
                                .exclusively(before: TapGesture().onEnded { composed = L("page.mouse.gestures.wasSingle") }))
                }
                NestedGestureBoxes()
            }
        }
    }

    /// A target to click: its name, and what it has heard.
    private func tile(_ key: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(L(key)).bold()
            Text(value).foregroundStyle(.palette.accent)
        }
        .frame(width: 16, alignment: .center)
        .padding(.vertical, 1)
        .border(.palette.border)
    }
}

/// A parent's tap against its child's, in two boxes: each is a parent with a
/// tap of its own, and its counts line is a child with a tap of its own.
///
/// Click the counts line. By default the child's tap wins and the parent never
/// hears it; `.highPriorityGesture(TapGesture())` on the first box's parent
/// gives the click to the PARENT alone (only "parent" rises), and
/// `.simultaneousGesture(TapGesture())` on the second's lets BOTH hear it.
/// Click anywhere else in a box — its title, its border — and only the parent
/// is there to hear it, in both.
struct NestedGestureBoxes: View {
    @State private var priority = Counts()
    @State private var simultaneous = Counts()

    /// The words the counts line is made of, and the boxes' titles.
    var childLabel = L("page.mouse.gestures.child")
    var parentLabel = L("page.mouse.gestures.parent")
    var priorityTitle = L("page.mouse.gestures.highPriority")
    var simultaneousTitle = L("page.mouse.gestures.simultaneous")

    /// How many taps a child and its parent have each heard.
    struct Counts {
        var child = 0
        var parent = 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            box(priorityTitle, priority) { priority.child += 1 }
                .highPriorityGesture(TapGesture().onEnded { priority.parent += 1 })
            box(simultaneousTitle, simultaneous) { simultaneous.child += 1 }
                .simultaneousGesture(TapGesture().onEnded { simultaneous.parent += 1 })
        }
    }

    /// A parent box whose counts line is a child with a tap of its own.
    private func box(_ title: String, _ counts: Counts, childTapped: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: title).bold()
            Text(verbatim: "\(childLabel) \(counts.child) · \(parentLabel) \(counts.parent)")
                .foregroundStyle(.palette.accent)
                .onTapGesture(perform: childTapped)
        }
        .frame(width: 34, alignment: .center)
        .padding(.vertical, 1)
        .border(.palette.border)
    }
}
