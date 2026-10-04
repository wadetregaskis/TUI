//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// What crosses is TEXT, in both directions: a terminal's clipboard holds a
    /// string. A copy writes every item that can be read as a string, one per
    /// line, and an item that cannot be (an image, a file promise) is not
    /// written. A paste offers one item, the clipboard's text, and triggers only
    /// if one of `supportedContentTypes` accepts text.
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
        ///     preferred first. The command triggers only if the clipboard's
        ///     text conforms to one of them (`.text`, `.plainText`,
        ///     `.utf8PlainText`, …).
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
            clipboardCommand("v") { event, clipboard in
                let text: String?
                if case .paste(let pasted) = event.key { text = pasted } else { text = clipboard.read() }
                guard let text, !text.isEmpty else { return false }
                let item = NSItemProvider(object: text as NSString)
                guard supportedContentTypes.contains(where: { item.hasItemConformingToTypeIdentifier($0.identifier) }),
                    let payload = validator([item])
                else { return false }
                payloadAction(payload)
                return true
            }
        }
    }

    // MARK: - Writing items

    /// How a copy or cut puts item providers on a terminal's clipboard.
    enum ClipboardCommand {
        /// Writes the text of every item that has one, one per line, in the
        /// order given, once all of them have loaded.
        ///
        /// An item loads its value asynchronously, on a queue of its choosing,
        /// so the write happens on the main actor once the last has answered —
        /// which is where a text field writes the clipboard too.
        static func write(_ items: [NSItemProvider], to clipboard: ClipboardAccess) {
            let readable = items.filter { $0.canLoadObject(ofClass: NSString.self) }
            guard !readable.isEmpty else { return }
            let texts = LoadedTexts(count: readable.count)
            let group = DispatchGroup()
            for (index, item) in readable.enumerated() {
                group.enter()
                _ = item.loadObject(ofClass: NSString.self) { object, _ in
                    texts.set(index, (object as? NSString).map { $0 as String })
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let joined = texts.all.compactMap { $0 }.joined(separator: "\n")
                if !joined.isEmpty { clipboard.write(joined) }
            }
        }

        /// The loaded texts, filled from the providers' queues.
        private final class LoadedTexts: @unchecked Sendable {
            private let lock = NSLock()
            private var texts: [String?]

            init(count: Int) { texts = Array(repeating: nil, count: count) }

            func set(_ index: Int, _ text: String?) {
                lock.lock()
                texts[index] = text
                lock.unlock()
            }

            var all: [String?] {
                lock.lock()
                defer { lock.unlock() }
                return texts
            }
        }
    }
#endif
