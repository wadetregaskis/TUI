//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseStep+Playing.swift
//
//  How a perf case's page is made and its steps are taken, shared by the
//  counting player (`CasePlayer`, `--check-counts`) and the session that
//  plays a case over time (`CaseSession`, `--session case:<id>`), so the two
//  build the same app and play a script alike.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI
import TUICore

extension CaseStep {
    /// The input this step delivers to a screen of `size`, keys before mouse
    /// events: none for a step that is not input. `pointer` is where the last
    /// hover left the pointer, and a hover moves it.
    ///
    /// A wheel turns over the screen's middle; a hover starts at the top of
    /// its middle column and moves down or up it, clamped to the screen.
    /// `type:` is a key per character: the player draws frames between them.
    func input(
        size: (width: Int, height: Int), pointer: inout (x: Int, y: Int)?
    ) -> (keys: [KeyEvent], mouse: [MouseEvent]) {
        switch self {
        case .wheel(let ticks):
            let button: MouseButton = ticks > 0 ? .scrollDown : .scrollUp
            let event = MouseEvent(button: button, phase: .scrolled, x: size.width / 2, y: size.height / 2)
            return ([], Array(repeating: event, count: abs(ticks)))
        case .key(let key):
            return ([key.event], [])
        case .type(let text):
            return (text.map { KeyEvent(key: .character($0)) }, [])
        case .hover(let rows):
            let start = pointer ?? (x: size.width / 2, y: 0)
            let moved = (x: start.x, y: max(0, min(size.height - 1, start.y + rows)))
            pointer = moved
            return ([], [MouseEvent(button: .none, phase: .moved, x: moved.x, y: moved.y)])
        case .open, .idle, .resize, .tick, .append, .editMiddle, .remove, .move, .replace:
            return ([], [])
        }
    }
}

extension CaseRows {
    /// Makes `step`'s write to the rows, outside any render; nothing for a
    /// step that writes nothing.
    func write(_ step: CaseStep) {
        switch step {
        case .append(let count): append(count)
        case .editMiddle: editMiddle()
        case .remove(let index): remove(at: index)
        case .move(let from, let to): move(from: from, to: to)
        case .replace: replace()
        case .open, .idle, .wheel, .key, .type, .hover, .resize, .tick: break
        }
    }
}

extension PerfCase {
    /// The case's page over `rows`, or an adopted scenario's at `count`, or
    /// `nil` for an adopted scenario `Stress` does not have.
    @MainActor
    func page(rows: CaseRows, count: Int, seed: UInt64) -> AnyView? {
        if case .adopted(let scenario, let variant) = composition {
            return CasePage.adopted(scenario: scenario, variant: variant, scale: count, seed: seed)
        }
        return AnyView(CasePage(composition: composition, container: container, rows: rows))
    }

    /// A headless app of the case's size, its page `page`, its scene saying
    /// whether the focus follows the pointer, and its locale and appearance
    /// pinned: what every play of a case draws in.
    @MainActor
    func app(page: AnyView) -> HeadlessApp {
        let app = HeadlessApp(
            CaseHost(page: page, followsPointer: composition.followsPointer), width: size.width, height: size.height)
        app.configureEnvironment { environment in
            environment.locale = Locale(identifier: "en_US")
            environment.colorScheme = .dark
        }
        return app
    }
}
