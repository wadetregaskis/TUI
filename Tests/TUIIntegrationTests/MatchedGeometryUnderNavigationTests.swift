//  🖥️ TUI — A Terminal UI framework for Swift
//  MatchedGeometryUnderNavigationTests.swift
//
//  A matched geometry group on a navigation stack's root, while a screen is
//  pushed over it: the root still draws, off-screen, and its drawing is
//  thrown away.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// A root with two tabs, `a` and `b`, as sources, and a bar under them
/// following the first; the screen it pushes reads where it is, which keeps
/// the carried origin in force, so the root's sources say where their owner
/// expects them.
private struct TabsRoot: View {
    let path: Binding<NavigationPath>
    @Namespace private var space

    var body: some View {
        NavigationStack(path: path) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    GlyphFill("a").frame(width: 4, height: 1).matchedGeometryEffect(id: 0, in: space)
                    GlyphFill("b").frame(width: 4, height: 1).matchedGeometryEffect(id: 1, in: space)
                }
                GlyphFill("_").frame(width: 4, height: 1)
                    .matchedGeometryEffect(id: 0, in: space, properties: .position, isSource: false)
            }
            .navigationDestination(for: Int.self) { _ in
                GeometryReader { proxy in Text(verbatim: "at \(proxy.frame(in: .global).minY)") }
            }
        }
    }
}

/// A root with a source `s`, and a screen with a follower `f` of it under a
/// line that reads where it is.
private struct FollowedAcross: View {
    let path: Binding<NavigationPath>
    @Namespace private var space

    var body: some View {
        NavigationStack(path: path) {
            GlyphFill("s").frame(width: 6, height: 2).matchedGeometryEffect(id: 0, in: space)
                .padding(.leading, 10)
                .navigationDestination(for: Int.self) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { proxy in Text(verbatim: "at \(proxy.frame(in: .global).minY)") }
                            .frame(height: 1)
                        GlyphFill("f").frame(width: 2, height: 1)
                            .matchedGeometryEffect(id: 0, in: space, isSource: false)
                    }
                }
        }
    }
}

@MainActor
@Suite("Matched geometry under a navigation stack")
struct MatchedGeometryUnderNavigationTests {

    @Test("A group on the covered root costs the frames no second walk")
    func coveredRootCostsNoCorrection() {
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })
        let harness = InputChainHarness(width: 40, height: 12)
        harness.frame(TabsRoot(path: binding))
        harness.frame(TabsRoot(path: binding))
        path.append(1)
        for _ in 0..<3 { harness.frame(TabsRoot(path: binding)) }
        let settled = harness.geometryCorrections
        // The root's members draw on every frame and are never found, their
        // drawing thrown away with the root's: none of them was drawn where
        // anyone sees it, so none was drawn from something wrong.
        for _ in 0..<5 { harness.frame(TabsRoot(path: binding)) }
        #expect(harness.geometryCorrections == settled)
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A follower on a pushed screen does not follow a source on the covered root")
    func followerDoesNotFollowTheCoveredRoot() {
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })
        let harness = InputChainHarness(width: 40, height: 12)
        harness.frame(FollowedAcross(path: binding))
        harness.frame(FollowedAcross(path: binding))
        path.append(1)
        for _ in 0..<3 { harness.frame(FollowedAcross(path: binding)) }
        let settled = harness.geometryCorrections
        var screen: [String] = []
        for _ in 0..<5 { screen = harness.frame(FollowedAcross(path: binding)).lines.map(\.stripped) }
        // Drawn where it is laid out — under the bar and the reader — and not
        // at the covered source, nor drawn there and then again.
        #expect(rect(of: "f", in: screen) == CellRect(x: 0, y: 3, width: 2, height: 1))
        #expect(harness.geometryCorrections == settled)
    }
}
