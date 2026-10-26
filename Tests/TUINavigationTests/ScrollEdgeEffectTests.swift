//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollEdgeEffectTests.swift
//
//  The scroll edge effects (refusal review O7, decisions A12) are honoured by
//  the medium: scrolled content never passes under a bar, so it stops at the
//  bar's edge, which is what `.automatic`, `.hard` and a hidden effect all
//  describe. These assert that guarantee — a bar's rows hold the bar alone and
//  the content resumes on the row after it, scrolled — and that the modifiers
//  leave it as it is, rather than asserting a no-op, which would keep passing
//  if the guarantee ever stopped holding.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
import TUINavigation
@testable import TUITestSupport

@MainActor
@Suite("Scroll edge effects", .rendersEnglishUI)
struct ScrollEdgeEffectTests {
    /// Thirty rows, scrolled to the end, so rows have passed the top bar.
    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { Text("row \($0)") }
            }
        }
        .defaultScrollAnchor(.bottom)
    }

    private func lines(_ view: some View, width: Int = 20, height: Int = 10) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height)).lines
            .map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private struct Planet: Hashable {
        let name: String
    }

    /// A navigation stack with the rows pushed, so its bar — the title row
    /// and the rule under it — is drawn above them. (A stack's root title goes
    /// to the window's top bar instead.)
    private func pushed(_ screen: some View) -> some View {
        var path = NavigationPath()
        path.append(Planet(name: "Mars"))
        let binding = Binding(get: { path }, set: { path = $0 })
        return NavigationStack(path: binding) {
            Text("root")
                .navigationTitle("Planets")
                .navigationDestination(for: Planet.self) { _ in screen.navigationTitle("Mars") }
        }
    }

    /// The row numbers on `lines`, in order.
    private func rowNumbers(_ lines: some Sequence<String>) -> [Int] {
        lines.compactMap { line in
            guard let match = line.firstMatch(of: /row (\d+)/) else { return nil }
            return Int(match.1)
        }
    }

    /// Scrolled content in `lines` stops at the bars: the `top` rows above and
    /// the `bottom` rows below hold no content, the row after the top bar is
    /// content, and the rows shown run on unbroken to the last.
    private func expectStopsAtBars(_ lines: [String], top: Int, bottom: Int, _ comment: String) {
        let topBar = lines.prefix(top)
        let bottomBar = lines.suffix(bottom)
        #expect(rowNumbers(topBar).isEmpty && rowNumbers(bottomBar).isEmpty, "nothing passes under a bar (\(comment)): \(lines)")
        let content = Array(lines.dropFirst(top).dropLast(bottom))
        let shown = rowNumbers(content)
        #expect(shown.last == 29, "scrolled to the end (\(comment)): \(lines)")
        #expect(shown == Array((shown.first ?? 0)...(shown.last ?? 0)), "unbroken (\(comment)): \(lines)")
        #expect(shown.first.map { $0 > 0 } == true, "rows have scrolled past the top (\(comment)): \(lines)")
        #expect(content.first.map { !rowNumbers([$0]).isEmpty } == true, "content resumes on the row after the bar (\(comment)): \(lines)")
    }

    @Test("Scrolled content stops at a safeAreaBar, whatever the effect asked for")
    func safeAreaBars() {
        let plain = lines(
            rows.safeAreaBar(edge: .top) { Text("BAR") }.safeAreaBar(edge: .bottom) { Text("END") })
        #expect(plain.first == "BAR" && plain.last == "END", "\(plain)")
        expectStopsAtBars(plain, top: 1, bottom: 1, "plain")
        let hard = lines(
            rows.safeAreaBar(edge: .top) { Text("BAR") }.safeAreaBar(edge: .bottom) { Text("END") }
                .scrollEdgeEffectStyle(.hard, for: .all))
        let automatic = lines(
            rows.scrollEdgeEffectStyle(.automatic, for: .vertical)
                .safeAreaBar(edge: .top) { Text("BAR") }.safeAreaBar(edge: .bottom) { Text("END") })
        let hidden = lines(
            rows.safeAreaBar(edge: .top) { Text("BAR") }.safeAreaBar(edge: .bottom) { Text("END") }
                .scrollEdgeEffectHidden())
        let inherited = lines(
            rows.scrollEdgeEffectStyle(nil, for: .top).scrollEdgeEffectHidden(false, for: .bottom)
                .safeAreaBar(edge: .top) { Text("BAR") }.safeAreaBar(edge: .bottom) { Text("END") })
        for (name, drawn) in [("hard", hard), ("automatic", automatic), ("hidden", hidden), ("inherited", inherited)] {
            expectStopsAtBars(drawn, top: 1, bottom: 1, name)
            #expect(drawn == plain, "\(name) draws as the plain view does: \(drawn)")
        }
    }

    @Test("Scrolled content stops at a navigation bar, whatever the effect asked for")
    func navigationBar() {
        let plain = lines(pushed(rows), width: 30)
        #expect(plain.first?.contains("Mars") == true && plain.dropFirst().first?.contains("─") == true, "\(plain)")
        expectStopsAtBars(plain, top: 2, bottom: 0, "plain")
        let hard = lines(pushed(rows.scrollEdgeEffectStyle(.hard, for: .top)), width: 30)
        let hidden = lines(pushed(rows.scrollEdgeEffectHidden(true, for: .top)), width: 30)
        for (name, drawn) in [("hard", hard), ("hidden", hidden)] {
            expectStopsAtBars(drawn, top: 2, bottom: 0, name)
            #expect(drawn == plain, "\(name) draws as the plain view does: \(drawn)")
        }
    }
}
