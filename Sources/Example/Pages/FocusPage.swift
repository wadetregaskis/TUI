//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Focus & raw-input demo page.
///
/// Demonstrates explicit focus identity and grouping (`.focusID` / `.focusSection`)
/// alongside the raw key handler (`.onKeyEvent`):
/// - Two labelled focus sections you can Tab through, with a live readout of the
///   currently focused element's `focusID`.
/// - A live "last key pressed" logger fed by `.onKeyEvent`.
struct FocusPage: View {
    @State private var lastKey: String = "—"

    /// Bound to a plain `Text` made focusable with `.focusable()` — proof that
    /// `.focused()`/`@FocusState` now work on any view, not just controls.
    @FocusState private var labelFocused: Bool

    // The focus manager publishes the currently focused element's id; reading it
    // in `body` re-evaluates each render, and a focus change requests a re-render,
    // so the readout below tracks the focus live as you Tab around.
    @Environment(\.focusManager) private var focusManager

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.focus.sectionsSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.focus.sectionsDescription")
                        .foregroundStyle(.palette.foregroundSecondary)

                    HStack(spacing: 3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("page.focus.sectionA").dim()
                            Button("A · One") {}.focusID("focus-a-one")
                            Button("A · Two") {}.focusID("focus-a-two")
                        }
                        .focusSection("focus-section-a")

                        VStack(alignment: .leading, spacing: 0) {
                            Text("page.focus.sectionB").dim()
                            Button("B · One") {}.focusID("focus-b-one")
                            Button("B · Two") {}.focusID("focus-b-two")
                        }
                        .focusSection("focus-section-b")
                    }

                    // One line, cut in the middle: a control given no
                    // `.focusID` is known by its identity path, which is as long
                    // as the view tree is deep.
                    ValueDisplayRow(
                        "page.focus.focusedID",
                        focusManager?.currentFocusedID ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            DemoSection("page.focus.focusableSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.focus.focusableExplain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // A single plain Text — not a control — made a Tab stop with
                    // .focusable() and bound to @FocusState via .focused(). It
                    // gains a "(focused)" suffix while it holds focus.
                    Text(
                        labelFocused
                            ? L("page.focus.focusableFocused")
                            : L("page.focus.focusableUnfocused"))
                        .focusable()
                        .focused($labelFocused)
                }
            }

            KeyPressDemo()

            CommandsDemo()

            FocusScopeDemo()

            DemoSection("page.focus.keyLoggerSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.focus.keyLoggerDescription")
                        .foregroundStyle(.palette.foregroundSecondary)
                    ValueDisplayRow("page.focus.lastKey", lastKey)
                }
            }

            Spacer()
        }
        .onKeyEvent { event in
            lastKey = describeKey(event)
            // Don't consume — let Tab (focus), Esc (back) and everything else
            // continue through the dispatch chain.
            return false
        }
        .scrollableDemoPage()
        .navigationTitle("menu.item.focus")
    }

    // MARK: - Helpers

    /// A key event as the logger shows it: named as TUIkit names every key,
    /// macOS's way — the modifiers in the order ⌃ ⌥ ⇧ ⌘, then the key (`⌃⇧Z`,
    /// `⇧⇥`, `⎋`, `F5`) — or "(paste)" for pasted text, which is not a key.
    private func describeKey(_ event: KeyEvent) -> String {
        event.displayString ?? "(paste)"
    }
}
