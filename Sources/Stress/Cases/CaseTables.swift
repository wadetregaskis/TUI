//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseTables.swift
//
//  Every table of perf cases, one per family of situations, each in its own
//  file under `Tables/` so lanes adding cases to different families never
//  touch the same lines.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The perf-case tables, in the order `--check-counts` plays them.
enum CaseTables {
    static let all: [CaseTableSource] = [lists, tables, scrolling, composites, editors, adopted]
}
