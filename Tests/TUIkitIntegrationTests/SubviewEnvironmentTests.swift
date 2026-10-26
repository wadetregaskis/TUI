//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SubviewEnvironmentTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// Which word a highlighter shows as chosen, kept outside the view so the test
/// can change it between frames as a write would.
@MainActor
private final class Chosen {
    var index = 0
}

/// A container that inks the subviews its caller hands it by its own state:
/// the chosen one red, the others green. The subviews render at the identity
/// they resolved to — the CALLER's, a `ForEach`'s rows here, each memoized
/// there — so the ink is the only thing that changes about them when the
/// choice moves.
private struct Highlighter<Content: View>: View {
    let chosen: Chosen
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { subviews in
            HStack(spacing: 1) {
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index].foregroundStyle(index == chosen.index ? Color.red : Color.green)
                }
            }
        }
    }
}

@MainActor
@Suite("A subview drawn under a new environment draws anew")
struct SubviewEnvironmentTests {
    @Test("A container that inks its subviews by its state re-inks them when the state moves")
    func reinksOnTheContainersState() {
        let chosen = Chosen()
        let harness = InputChainHarness(width: 20, height: 2)
        let page = {
            // Rows of a `ForEach`, as a picker's options often are: each is
            // memoized at its own identity.
            Highlighter(chosen: chosen) {
                ForEach(["one", "two"], id: \.self) { Text($0) }
            }
        }
        _ = harness.frame(page())
        let before = harness.frame(page()).lines[0]
        chosen.index = 1
        let after = harness.frame(page()).lines[0]
        #expect(before.stripped == after.stripped)
        #expect(before != after, "the ink did not move with the choice: \(after.debugDescription)")
    }
}
