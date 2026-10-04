//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PasteButton.swift
//
//  SwiftUI's `PasteButton`: a button that reads the clipboard and hands what
//  it holds to an action.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import UniformTypeIdentifiers
#endif

/// A system button that reads items from the clipboard and delivers them to a
/// closure — mirrors SwiftUI's `PasteButton`.
///
/// Titled "Paste" in the current language. SwiftUI's button is disabled while
/// the pasteboard holds nothing it can take; a terminal app cannot watch its
/// clipboard (reading it runs a program), so this one is always enabled, and a
/// press finds out — a clipboard that cannot be had as the payload type pastes
/// nothing. What it can be had as is ``View/pasteDestination(for:action:validator:)``'s
/// rule: values this app copied, else the clipboard's text.
public struct PasteButton: View {
    private let paste: @MainActor (ClipboardAccess) -> Void

    @Environment(\.clipboardAccess) private var clipboard
    @Environment(\.typedClipboard) private var typedClipboard

    /// Creates a paste button that delivers the clipboard's contents as
    /// `payloadType`.
    ///
    /// - Parameters:
    ///   - payloadType: The type the clipboard's contents are read as.
    ///   - onPaste: Receives the pasted items.
    public init<T>(payloadType: T.Type, onPaste: @escaping ([T]) -> Void) {
        self.paste = { clipboard in
            guard let text = clipboard.read(), !text.isEmpty,
                let items = clipboard.paste(text, as: T.self)
            else { return }
            onPaste(items)
        }
    }

    public var body: some View {
        // Read off the wrappers when the button is drawn, for the press: an
        // event closure sees no environment of its own.
        var clipboard = self.clipboard
        clipboard.typed = clipboard.typed ?? typedClipboard
        let paste = self.paste
        return Button {
            paste(clipboard)
        } label: {
            Label {
                Text(LocalizationService.shared.string(for: .paste))
            } icon: {
                Image(systemName: "doc.on.clipboard")
            }
        }
    }
}

#if canImport(UniformTypeIdentifiers)
    extension PasteButton {
        /// Creates a paste button that delivers the clipboard's text as an item
        /// provider, if it conforms to one of `supportedContentTypes`.
        ///
        /// - Parameters:
        ///   - supportedContentTypes: The types the button accepts. The
        ///     clipboard holds text, so one of them must accept text.
        ///   - payloadAction: Receives the pasted items.
        public init(supportedContentTypes: [UTType], payloadAction: @escaping ([NSItemProvider]) -> Void) {
            self.paste = { clipboard in
                guard let text = clipboard.read(), !text.isEmpty else { return }
                let item = NSItemProvider(object: text as NSString)
                guard supportedContentTypes.contains(where: { item.hasItemConformingToTypeIdentifier($0.identifier) })
                else { return }
                payloadAction([item])
            }
        }
    }
#endif

// MARK: - Environment without reflection

extension PasteButton: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _clipboard.resolveEnvironment(environment)
        _typedClipboard.resolveEnvironment(environment)
    }
}
