//  🖥️ TUI — A Terminal UI framework for Swift
//  ClipboardCommandTests.swift
//
//  SwiftUI's copy, cut and paste commands: SwiftUI's ⌘C, ⌘X and ⌘V resolved
//  through \.commandKey (Control by default), and a bracketed paste for the
//  paste; heard on the focus path once the focused control lets the key go;
//  only text crossing, in either direction. Apple platforms only — the
//  payloads are NSItemProviders and the types UTTypes.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import Testing
    import UniformTypeIdentifiers

    import TUIApp
    @testable import TUIAppTestSupport
    @testable import TUICore
    @testable import TUIFoundation
    @testable import TUITestSupport
    import TUITextInput

    /// What the actions under test saw, in the order they ran.
    private final class ActionLog: @unchecked Sendable {
        var entries: [String] = []
    }

    private func control(_ letter: Character) -> KeyEvent {
        KeyEvent(key: .character(letter), ctrl: true)
    }

    @MainActor
    @Suite("SwiftUI's copy, cut and paste commands")
    struct ClipboardCommandTests {

        @Test("Copy writes the items' text to the clipboard on the ⌘C stand-in")
        func copyWritesText() async {
            let board = FakeClipboard()
            let harness = InputChainHarness { $0.clipboardAccess = board.access }
            let consumed = harness.play([control("c")]) {
                Text("leaf").focusable()
                    .onCopyCommand {
                        [NSItemProvider(object: "first" as NSString), NSItemProvider(object: "second" as NSString)]
                    }
            }
            #expect(consumed == [true])
            await settle(until: { !board.writes.isEmpty })
            #expect(board.writes == ["first\nsecond"])
        }

        @Test("Cut runs its action and writes what it returns; a nil one keeps the key and does nothing")
        func cutAndNil() async {
            let board = FakeClipboard()
            let log = ActionLog()
            let harness = InputChainHarness { $0.clipboardAccess = board.access }
            harness.play([control("x"), control("c")]) {
                VStack {
                    Text("leaf").focusable()
                        .onCutCommand {
                            log.entries.append("cut")
                            return [NSItemProvider(object: "gone" as NSString)]
                        }
                        .onCopyCommand(perform: nil)
                }
                .onCopyCommand {
                    log.entries.append("outer copy")
                    return []
                }
            }
            await settle(until: { !board.writes.isEmpty })
            #expect(board.writes == ["gone"])
            #expect(log.entries == ["cut"], "the nil copy kept ⌃C from the container")
        }

        @Test("The chord follows \\.commandKey, as any ⌘ shortcut does")
        func chordFollowsCommandKey() {
            for (event, expected) in [(control("c"), [String]()), (KeyEvent(key: .character("c"), alt: true), ["copy"])] {
                let log = ActionLog()
                let harness = InputChainHarness()
                harness.play([event]) {
                    Text("leaf").focusable()
                        .onCopyCommand {
                            log.entries.append("copy")
                            return []
                        }
                        .commandKey(.option)
                }
                #expect(log.entries == expected, "under .option, ⌥C copies and ⌃C does not: \(event)")
            }
        }

        @Test("Paste triggers on a bracketed paste or the ⌘V stand-in, for a type that accepts text")
        func pasteText() {
            let board = FakeClipboard(contents: "from the clipboard")
            let log = ActionLog()
            let harness = InputChainHarness { $0.clipboardAccess = board.access }
            harness.play([KeyEvent(key: .paste("pasted")), control("v")]) {
                VStack {
                    Text("leaf").focusable()
                        .onPasteCommand(of: [.image]) { _ in log.entries.append("image") }
                }
                .onPasteCommand(of: [.plainText]) { items in
                    log.entries.append("items \(items.count)")
                }
            }
            #expect(log.entries == ["items 1", "items 1"], "the image paste never triggered, and kept nothing")
        }

        @Test("A validator that returns nil keeps the paste from triggering")
        func pasteValidator() {
            let log = ActionLog()
            let harness = InputChainHarness()
            harness.play([KeyEvent(key: .paste("no")), KeyEvent(key: .paste("yes"))]) {
                Text("leaf").focusable()
                    .onPasteCommand(of: [.text]) { items -> Int? in
                        log.entries.append("validated")
                        return items.isEmpty ? nil : log.entries.count
                    } perform: { count in
                        log.entries.append("performed \(count)")
                    }
            }
            #expect(log.entries == ["validated", "performed 1", "validated", "performed 3"])
        }

        @Test("A focused text field keeps its own copy and paste")
        func textFieldFirst() {
            final class Text0: @unchecked Sendable { var value = "" }
            let text = Text0()
            let log = ActionLog()
            let harness = InputChainHarness()
            harness.play([KeyEvent(key: .paste("typed"))]) {
                VStack {
                    TextField("Name", text: Binding(get: { text.value }, set: { text.value = $0 }))
                }
                .onPasteCommand(of: [.text]) { _ in log.entries.append("paste command") }
            }
            #expect(text.value == "typed")
            #expect(log.entries.isEmpty)
        }
    }
#endif
