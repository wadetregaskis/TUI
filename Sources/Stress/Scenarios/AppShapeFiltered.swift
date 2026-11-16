//  🖥️ TUI — A Terminal UI framework for Swift
//  AppShapeFiltered.swift
//
//  Long collections an app filters in its body, so the rows arrive in a new
//  array every frame: a `.columns` form of settings, and a two-axis lazy stack
//  of source lines. The shape every width kept from one frame to the next and
//  compared against the rows is priced on, as `sidebar-filtered` prices a
//  hugged `List`'s. See `AppShapes.swift` for why the applications exist at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - The data

/// A setting a `.columns` form lists: its key and its value.
struct FilteredSetting: Identifiable, Sendable, Equatable {
    let id: Int
    let key: String
    let value: String
    /// Whether the setting holds its default, which the form's filter hides.
    let isDefault: Bool

    static func sample(_ index: Int, seed: UInt64) -> Self {
        let h = mix(seed, index)
        return Self(
            id: index, key: "\(Synth.slug(h)).\(Synth.slug(h >> 16))", value: Synth.status(h >> 8),
            isDefault: h.isMultiple(of: 20))
    }
}

/// A line of source: its number and its text.
struct FilteredLine: Identifiable, Sendable, Equatable {
    let id: Int
    let text: String
    /// Whether the line is blank, which the editor's filter hides.
    let isBlank: Bool

    static func sample(_ index: Int, seed: UInt64) -> Self {
        let h = mix(seed, index)
        let indent = String(repeating: " ", count: Int(h % 4) * 4)
        return Self(
            id: index, text: indent + Synth.sentence(h >> 4, words: 3 + Int(h % 9)), isBlank: h.isMultiple(of: 20))
    }
}

// MARK: - The settings form

/// Two thousand settings in a `.columns` form in scroll content, those holding
/// their default filtered out in the body: a new array of rows every frame.
///
/// The form builds only the rows on screen past the lazy stack's threshold,
/// and keeps its label column and its rows' width, read once from every row,
/// while the rows are the same (`FormColumnsWindowing.swift`). Each time the
/// form is laid out it compares the rows it is handed with the ones it kept.
struct FilteredColumnsFormApp: View {
    /// Synthesised once, like an app's settings.
    let settings: [FilteredSetting]

    init(count: Int, seed: UInt64) {
        self.settings = (0..<count).map { FilteredSetting.sample($0, seed: seed) }
    }

    var body: some View {
        // What a "modified only" filter shows, and a new array each time the
        // body runs.
        let shown = settings.filter { !$0.isDefault }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "columns-form-filtered", shown.count)).bold()
            ScrollView {
                Form {
                    ForEach(shown) { setting in
                        LabeledContent(setting.key, value: setting.value)
                    }
                }
                .formStyle(.columns)
            }
            HStack(spacing: 2) {
                Spacer()
                // In a leaf, for the reason `TickStamp` gives.
                TickStamp()
            }
        }
    }
}

// MARK: - The filtered editor

/// Two thousand source lines in a lazy stack scrolled on both axes, the blank
/// ones filtered out in the body: a new array of rows every frame.
///
/// A two-axis scroll view asks the stack for the width of its widest row over
/// every row, several times a frame, and the stack keeps that width while the
/// rows are the same (`StackContentWidth.swift`), comparing the rows it is
/// handed with the ones it kept on each ask. `code-editor` loops over a range,
/// which compares in O(1), so it never prices that compare.
struct FilteredEditorApp: View {
    /// Synthesised once, like a document.
    let lines: [FilteredLine]

    init(count: Int, seed: UInt64) {
        self.lines = (0..<count).map { FilteredLine.sample($0, seed: seed) }
    }

    var body: some View {
        // What a "hide blank lines" view shows, and a new array each time the
        // body runs.
        let shown = lines.filter { !$0.isBlank }
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.app-shapes.heading", "code-editor-filtered", shown.count)).bold()
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { line in
                        HStack(spacing: 1) {
                            Text((line.id + 1).digits(width: 5, padding: " ")).foregroundStyle(.gray)
                            Text(verbatim: line.text)
                        }
                    }
                }
            }
            HStack(spacing: 2) {
                Spacer()
                // In a leaf, for the reason `TickStamp` gives.
                TickStamp()
            }
        }
    }
}
