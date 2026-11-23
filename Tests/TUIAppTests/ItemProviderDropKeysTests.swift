//  🖥️ TUI — A Terminal UI framework for Swift
//  ItemProviderDropKeysTests.swift
//
//  An `onDrop` from the keyboard (hunt H-35, DND-4; the owner's rule that no
//  interaction is mouse-only): it is a focus stop, as a `dropDestination` is,
//  so a drag carried from the keyboard can stop there and Return drops it,
//  and Paste on it drops what was copied. Apple platforms only: the payloads
//  are NSItemProviders and the types UTTypes.
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

    /// What the destination under test was handed, in order.
    private final class Log: @unchecked Sendable {
        var providers: [NSItemProvider] = []
        var entries: [String] = []
        var pressed: [String] = []
    }

    /// A delegate that logs every call and takes every drop.
    @MainActor
    private struct LoggingDelegate: DropDelegate {
        let log: Log

        func validateDrop(info: DropInfo) -> Bool {
            log.entries.append("validate")
            return true
        }
        func dropEntered(info: DropInfo) { log.entries.append("entered") }
        func dropUpdated(info: DropInfo) -> DropProposal? {
            log.entries.append("updated")
            return nil
        }
        func dropExited(info: DropInfo) { log.entries.append("exited") }
        func performDrop(info: DropInfo) -> Bool {
            log.providers += info.itemProviders(for: [.text])
            log.entries.append("perform")
            return true
        }
    }

    private let pickUp = KeyEvent(key: .character("r"), ctrl: true)

    private func control(_ letter: Character) -> KeyEvent {
        KeyEvent(key: .character(letter), ctrl: true)
    }

    @MainActor
    @Suite("An onDrop from the keyboard")
    struct ItemProviderDropKeysTests {
        /// A harness whose clipboard is `board`'s, with a typed clipboard.
        private func harness(_ board: FakeClipboard) -> InputChainHarness {
            let typed = TypedClipboard()
            return InputChainHarness {
                $0.clipboardAccess = board.access
                $0.typedClipboard = typed
            }
        }

        /// An `onDrag` card, a button, and a bin that takes text, down the page.
        private func board(_ provider: NSItemProvider, _ log: Log, types: [UTType] = [.text]) -> some View {
            VStack(alignment: .leading) {
                Text("card").onDrag { provider }
                Button("other") { log.pressed.append("other") }
                Text("bin").onDrop(of: types, isTargeted: nil) { providers in
                    log.providers += providers
                    return true
                }
            }
        }

        @Test("Ctrl-R picks an onDrag up, Tab goes straight to the onDrop that takes it, and Return drops its provider")
        func carryAndDrop() {
            let log = Log()
            let provider = NSItemProvider(object: "ace" as NSString)
            let harness = InputChainHarness()
            let consumed = harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) { board(provider, log) }
            #expect(consumed == [true, true, true])
            #expect(log.providers.count == 1 && log.providers.first === provider, "\(log.providers)")
            #expect(log.pressed.isEmpty, "the button between them was passed over")
            #expect(harness.tui.dragAndDropSession.active == nil)
        }

        @Test("An onDrop that does not take what is carried is no stop for it")
        func carrySkipsAnOtherType() {
            let log = Log()
            let provider = NSItemProvider(object: "ace" as NSString)
            let harness = InputChainHarness()
            harness.play([pickUp]) { board(provider, log, types: [.image]) }
            #expect(harness.tui.dragAndDropSession.carryCues.isEmpty, "nothing but the card can take it")
        }

        @Test("A delegate's drop from a carry is validated, entered, updated and performed")
        func carryToADelegate() {
            let log = Log()
            let harness = InputChainHarness()
            harness.play([pickUp, KeyEvent(key: .tab), KeyEvent(key: .enter)]) {
                VStack(alignment: .leading) {
                    Text("card").draggable("ace")
                    Text("bin").onDrop(of: [.text], delegate: LoggingDelegate(log: log))
                }
            }
            #expect(log.entries.first == "validate" && log.entries.last == "perform", "\(log.entries)")
            #expect(log.providers.count == 1)
        }

        @Test("Copy on a focused onDrag, Tab, and Paste on the onDrop drops the same provider there")
        func copyThenPaste() {
            let board = FakeClipboard()
            let log = Log()
            let provider = NSItemProvider(object: "ace" as NSString)
            let consumed = harness(board).play([control("c"), KeyEvent(key: .tab), KeyEvent(key: .tab), control("v")]) {
                self.board(provider, log)
            }
            #expect(consumed == [true, true, true, true])
            #expect(log.providers.count == 1 && log.providers.first === provider, "\(log.providers)")
        }

        @Test("Paste of text on a focused onDrop of text drops it as a provider of text")
        func pasteText() {
            let log = Log()
            let consumed = harness(FakeClipboard(contents: "plum")).play([KeyEvent(key: .tab), control("v")]) {
                Text("bin").onDrop(of: [.plainText], isTargeted: nil) { providers in
                    log.providers += providers
                    return true
                }
            }
            #expect(consumed == [true, true])
            #expect(log.providers.count == 1)
            #expect(log.providers.first?.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) == true)
        }

        @Test("Paste on a delegate's view makes the whole of a drop's calls, every time")
        func pasteToADelegate() {
            let log = Log()
            harness(FakeClipboard(contents: "plum")).play([KeyEvent(key: .tab), control("v"), control("v")]) {
                Text("bin").onDrop(of: [.text], delegate: LoggingDelegate(log: log))
            }
            let drop = ["validate", "entered", "updated", "perform"]
            #expect(log.entries == drop + drop)
        }

        @Test("Paste of text on an onDrop that takes no text is not answered")
        func pasteOfAnOtherType() {
            let log = Log()
            let consumed = harness(FakeClipboard(contents: "plum")).play([KeyEvent(key: .tab), control("v")]) {
                Text("bin").onDrop(of: [.image], isTargeted: nil) { providers in
                    log.providers += providers
                    return true
                }
            }
            #expect(consumed.last == false)
            #expect(log.providers.isEmpty)
        }
    }
#endif
