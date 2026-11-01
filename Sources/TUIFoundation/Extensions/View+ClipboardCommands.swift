//  🖥️ TUI — A Terminal UI framework for Swift
//  View+ClipboardCommands.swift
//
//  SwiftUI's copy, cut and paste commands. Their payloads are NSItemProviders
//  and their types UTTypes, which exist only where UniformTypeIdentifiers
//  does, so on Linux these are absent rather than half there.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import Synchronization
    import UniformTypeIdentifiers

    // MARK: - Commands

    /// SwiftUI's copy, cut and paste commands. Like its move, exit and delete
    /// commands (see ``View/onMoveCommand(perform:)``), each is heard while the
    /// focus is on the view or inside it, once the focused control lets the key
    /// go, and the innermost handler takes it.
    ///
    /// The keys are SwiftUI's ⌘C, ⌘X and ⌘V, resolved through
    /// ``EnvironmentValues/commandKey`` like any other ⌘ shortcut — Control-C,
    /// Control-X and Control-V by default. A paste is also the terminal's own:
    /// its Paste (⌘V in the terminal application) arrives as a bracketed paste,
    /// which reaches a paste command whenever the focused control does not take
    /// it, as a text field does.
    ///
    /// What crosses is TEXT on most terminals, whose clipboard holds a string:
    /// a copy writes every item that can be read as a string, one per line,
    /// and a paste offers one item, the clipboard's text. Where the terminal
    /// speaks OSC 5522 (``TerminalClient/mimeClipboard``), any type crosses: a
    /// copy writes, beside the text, every representation an item registers
    /// that has a MIME type — an image, a PDF, rich text — and a paste reads
    /// every type the clipboard holds that the focused view's paste commands
    /// accept (`supportedContentTypes`, by `UTType` conformance).
    extension View {
        /// Performs an action in response to the Copy command, writing the
        /// items it returns to the clipboard.
        ///
        /// - Parameter payloadAction: Returns the items to copy. `nil` disables
        ///   the command: the view keeps it and nothing is copied.
        /// - Returns: A view that handles the Copy command while it holds the
        ///   focus.
        public func onCopyCommand(perform payloadAction: (() -> [NSItemProvider])?) -> some View {
            clipboardCommand("c") { _, clipboard in
                if let payloadAction { ClipboardCommand.write(payloadAction(), to: clipboard) }
                return true
            }
        }

        /// Performs an action in response to the Cut command, writing the items
        /// it returns to the clipboard. The action deletes what it cuts.
        ///
        /// - Parameter payloadAction: Deletes the selection and returns the
        ///   items to put on the clipboard. `nil` disables the command: the
        ///   view keeps it and nothing is cut.
        /// - Returns: A view that handles the Cut command while it holds the
        ///   focus.
        public func onCutCommand(perform payloadAction: (() -> [NSItemProvider])?) -> some View {
            clipboardCommand("x") { _, clipboard in
                if let payloadAction { ClipboardCommand.write(payloadAction(), to: clipboard) }
                return true
            }
        }

        /// Performs an action in response to the Paste command, with the
        /// clipboard's items.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view accepts, most
        ///     preferred first. The command triggers only if what is pasted
        ///     conforms to one of them: its text (`.text`, `.plainText`,
        ///     `.utf8PlainText`, …) or, where the terminal hands over more
        ///     than text (OSC 5522 paste events), a picture (`.png`, `.image`)
        ///     or another of the clipboard's types.
        ///   - payloadAction: The action, given the pasted items.
        /// - Returns: A view that handles the Paste command while it holds the
        ///   focus.
        public func onPasteCommand(
            of supportedContentTypes: [UTType], perform payloadAction: @escaping ([NSItemProvider]) -> Void
        ) -> some View {
            onPasteCommand(of: supportedContentTypes, validator: { $0 }, perform: payloadAction)
        }

        /// Performs an action in response to the Paste command, with the
        /// clipboard's items once `validator` accepts them.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the view accepts, as for
        ///     ``onPasteCommand(of:perform:)``.
        ///   - validator: Decides whether the items can be pasted, and prepares
        ///     them. Returning `nil` keeps the command from triggering.
        ///   - payloadAction: The action, given what `validator` returned.
        /// - Returns: A view that handles the Paste command while it holds the
        ///   focus.
        public func onPasteCommand<Payload>(
            of supportedContentTypes: [UTType], validator: @escaping ([NSItemProvider]) -> Payload?,
            perform payloadAction: @escaping (Payload) -> Void
        ) -> some View {
            clipboardCommand("v", declares: { Self.takes($0, supportedContentTypes) }, perform: { event, clipboard in
                let text: String?
                if case .paste(let pasted) = event.key { text = pasted } else { text = clipboard.read() }
                guard let item = Self.pastedItem(text: text, attachments: event.pasteAttachments) else { return false }
                guard supportedContentTypes.contains(where: { item.hasItemConformingToTypeIdentifier($0.identifier) }),
                    let payload = validator([item])
                else { return false }
                payloadAction(payload)
                return true
            })
        }
    }

    // MARK: - What was pasted

    extension View {
        /// Whether a paste command of `types` takes `event`'s paste: its
        /// text, where a type accepts plain text, or one of the other types
        /// the terminal handed over, by `UTType` conformance — `.image` takes
        /// a PNG, `.pdf` a PDF. What the command declares, so an OSC 5522
        /// paste reads only the types something will take.
        static func takes(_ event: KeyEvent, _ types: [UTType]) -> Bool {
            guard case .paste(let text) = event.key else { return false }
            if !text.isEmpty, types.contains(where: { UTType.utf8PlainText.conforms(to: $0) }) { return true }
            return event.pasteAttachments.contains { attachment in
                guard let type = UTType(mimeType: attachment.type) else { return false }
                return types.contains(where: type.conforms(to:))
            }
        }

        /// What a paste offers a paste command: its text, and each of the
        /// clipboard's other types the terminal handed over, as the type a
        /// `UTType` names its MIME type; `nil` where it offers nothing.
        static func pastedItem(text: String?, attachments: [PasteAttachment]) -> NSItemProvider? {
            let text = text.flatMap { $0.isEmpty ? nil : $0 }
            guard text != nil || !attachments.isEmpty else { return nil }
            let item = text.map { NSItemProvider(object: $0 as NSString) } ?? NSItemProvider()
            for attachment in attachments {
                guard let type = UTType(mimeType: attachment.type) else { continue }
                let data = Data(attachment.bytes)
                item.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            return item
        }
    }

    // MARK: - Writing items

    /// How a copy or cut puts item providers on a terminal's clipboard.
    enum ClipboardCommand {
        /// Writes the text of every item that has one, one per line, in the
        /// order given, with every other representation the items register
        /// that has a MIME type beside it — where the terminal takes more
        /// than text (see ``ClipboardAccess/write(_:representations:announcingSuccess:)``)
        /// — once all of them have loaded.
        ///
        /// An item loads its value asynchronously, on a queue of its choosing,
        /// so the write happens on the main actor once the last has answered —
        /// which is where a text field writes the clipboard too.
        static func write(_ items: [NSItemProvider], to clipboard: ClipboardAccess) {
            let readable = items.filter { $0.canLoadObject(ofClass: NSString.self) }
            let typed = items.flatMap { item in
                item.registeredTypeIdentifiers.compactMap { identifier -> (NSItemProvider, String, String)? in
                    // Plain text is the copy's text already; styled text — HTML,
                    // RTF, which conform to `.text` too — is a representation.
                    guard let type = UTType(identifier), !type.conforms(to: .plainText),
                        let mime = type.preferredMIMEType
                    else { return nil }
                    return (item, identifier, mime)
                }
            }
            guard !readable.isEmpty || !typed.isEmpty else { return }
            let texts = LoadedTexts(count: readable.count)
            let datas = LoadedData(count: typed.count)
            let group = DispatchGroup()
            for (index, item) in readable.enumerated() {
                group.enter()
                _ = item.loadObject(ofClass: NSString.self) { object, _ in
                    texts.set(index, (object as? NSString).map { $0 as String })
                    group.leave()
                }
            }
            for (index, (item, identifier, mime)) in typed.enumerated() {
                group.enter()
                _ = item.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    datas.set(index, data.map { ClipboardRepresentation(type: mime, data: $0) })
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let joined = texts.all.compactMap { $0 }.joined(separator: "\n")
                let representations = datas.all.compactMap { $0 }
                if !joined.isEmpty || !representations.isEmpty {
                    clipboard.write(joined, representations: representations)
                }
            }
        }

        /// The loaded representations, filled from the providers' queues.
        private final class LoadedData: Sendable {
            private let parts: Mutex<[ClipboardRepresentation?]>

            init(count: Int) { parts = Mutex(Array(repeating: nil, count: count)) }

            func set(_ index: Int, _ part: ClipboardRepresentation?) {
                parts.withLock { $0[index] = part }
            }

            var all: [ClipboardRepresentation?] {
                parts.withLock { $0 }
            }
        }

        /// The loaded texts, filled from the providers' queues.
        private final class LoadedTexts: Sendable {
            private let texts: Mutex<[String?]>

            init(count: Int) { texts = Mutex(Array(repeating: nil, count: count)) }

            func set(_ index: Int, _ text: String?) {
                texts.withLock { $0[index] = text }
            }

            var all: [String?] {
                texts.withLock { $0 }
            }
        }
    }
#endif
