//  🖥️ TUI — A Terminal UI framework for Swift
//  Exports.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// TUITesting re-exports the module it is built on, as each module of the split
// does, so a test file that writes `import TUITesting` can already name `Key`,
// `CellPoint`, `App` and `View`. It is on no other module: a test of a `List`
// imports the `List`'s module, or `TUI`, as the app under test does, so what an
// app's tests compile and link is what the app does, and this module.
@_exported import TUIApp
