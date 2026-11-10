//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuWideLabelTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIApp
@testable import TUIFoundation
import TUIMenus
@testable import TUITestSupport

/// An inline menu hugs its widest row, and keeps it on one line when it scrolls.
/// The Example's main menu in Japanese wrapped "オーバーレイとモーダル" onto a
/// second line at every terminal width: the menu scrolled, and the scrollbar's
/// column came out of rows sized to that label exactly. English wrapped its
/// widest row the same way; a wide label was only where it was seen. The two
/// hugging cases are the controls, which passed before the fix.
@MainActor
@Suite("An inline menu keeps its widest row on one line")
struct MenuWideLabelTests {
    private func lines(_ items: some View, width: Int = 60, height: Int = 30) -> [String] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let buffer = renderToBuffer(Menu("デモを選択") { items }.menuStyle(.inline), context: context)
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    @Test("A Japanese row with a key equivalent stays on one line")
    func japaneseRowWithHint() {
        let drawn = lines(
            Group {
                Button("カラー") {}.keyboardShortcut("2", modifiers: [])
                Button("オーバーレイとモーダル") {}.keyboardShortcut("4", modifiers: [])
                Button("絵文字と SF Symbols") {}.keyboardShortcut(".", modifiers: [])
            })
        #expect(drawn.contains { $0.contains("オーバーレイとモーダル") }, "\(drawn.joined(separator: "\n"))")
    }

    @Test("A Japanese row without one stays on one line")
    func japaneseRowWithoutHint() {
        let drawn = lines(
            Group {
                Button("カラー") {}
                Button("オーバーレイとモーダル") {}
                Button("絵文字と SF Symbols") {}
            })
        #expect(drawn.contains { $0.contains("オーバーレイとモーダル") }, "\(drawn.joined(separator: "\n"))")
    }

    @Test("A Japanese row stays on one line in a menu that scrolls")
    func japaneseRowWhenScrolling() {
        let labels = [
            "テキストスタイル", "カラー", "コンテナビュー", "オーバーレイとモーダル", "レイアウトシステム",
            "ボタンとリンク", "トグル", "テキスト入力", "ラジオボタン", "スピナー", "リスト", "テーブル",
        ]
        let drawn = lines(
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button(label) {}.keyboardShortcut(KeyEquivalent(Character(String(index % 10))), modifiers: [])
            }, height: 10)
        #expect(drawn.contains { $0.contains("オーバーレイとモーダル") }, "\(drawn.joined(separator: "\n"))")
    }

    @Test("An English row that exactly fits stays on one line in a menu that scrolls")
    func englishRowWhenScrolling() {
        let labels = [
            "Text Styles", "Colors", "Container Views", "Overlays & Modals", "Layout System",
            "Buttons & Links", "Toggles", "Text Input", "Radio Buttons", "Spinners", "Lists", "Tables",
        ]
        let drawn = lines(
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button(label) {}.keyboardShortcut(KeyEquivalent(Character(String(index % 10))), modifiers: [])
            }, height: 10)
        #expect(drawn.contains { $0.contains("Overlays & Modals") }, "\(drawn.joined(separator: "\n"))")
    }
}
