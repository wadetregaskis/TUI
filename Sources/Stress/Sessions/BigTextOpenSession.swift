//  🖥️ TUI — A Terminal UI framework for Swift
//  BigTextOpenSession.swift
//
//  A large document opened again and again into a source pane: each step a
//  new TextEditor holding a few megabytes of JSON, so every frame is the
//  first frame of an editor, where `bigtext`'s are a key's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUI

// MARK: - The model

/// Which opening of the document the pane shows: a new one makes a new editor.
@Observable
@MainActor
final class BigTextOpenings {
    var text: String
    var opened = 0

    init(text: String) {
        self.text = text
    }
}

// MARK: - The page

/// tuitree's pane, as its M5 feedback, item 1, drew it: a tree beside the
/// source, under a heading, so the editor is measured by an `HStack` and a
/// `VStack` before its first render. `.id` gives each opening an editor of its
/// own, as opening a file replaces the pane's.
struct BigTextOpenPage: View {
    let openings: BigTextOpenings

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(verbatim: "Tree")
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "opened \(openings.opened) · \(openings.text.utf8.count) bytes")
                TextEditor(text: Binding(get: { openings.text }, set: { openings.text = $0 }))
                    .id(openings.opened)
            }
        }
    }
}

// MARK: - The script

/// Opens the document again each step: no key, only a new editor's first
/// frame — its measures and its render — over 3.2 MB of text.
@MainActor
final class BigTextOpenSession: StressSession {
    private let openings: BigTextOpenings

    init(config: StressConfig) {
        openings = BigTextOpenings(text: BigTextSession.documentText(config))
    }

    var page: BigTextOpenPage { BigTextOpenPage(openings: openings) }

    func step(_ index: Int) -> SessionStep {
        openings.opened += 1
        return SessionStep(action: "open")
    }

    /// The heading names the opening the model is on, and the editor's first
    /// row is the document's.
    func check(_ screen: [String], after index: Int) -> String? {
        let heading = "opened \(openings.opened) · \(openings.text.utf8.count) bytes"
        guard let first = screen.first, first.contains(heading) else { return "the heading does not say \(heading)" }
        guard screen.count > 1, screen[1].contains("[") else { return "the editor does not show the document's start" }
        return nil
    }

    static let descriptor = SessionDescriptor(
        id: "bigtext-open",
        summary: "a TextEditor of 3.2 MB of JSON opened afresh every step, beside a tree and under a heading",
        exercises: "an editor's first frame over a large document: its measures and its render, before it has a handler",
        make: { config, width, height, cold in
            DrivenSession(BigTextOpenSession(config: config), width: width, height: height, cold: cold)
        })
}
