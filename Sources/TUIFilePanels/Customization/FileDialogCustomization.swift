//  🖥️ TUI — A Terminal UI framework for Swift
//  FileDialogCustomization.swift
//
//  What SwiftUI's `fileDialog` modifiers say about the file panels presented
//  beneath them: one environment value, which a panel reads as it is
//  presented.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// What the `fileDialog` modifiers have set for the file panels beneath them.
///
/// Written as SwiftUI's are: outside the modifier that presents the panel,
///
/// ```swift
/// .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { … }
/// .fileDialogMessage("Choose the PDFs to combine")
/// .fileDialogConfirmationLabel("Combine")
/// ```
///
/// so each is an environment value the presenting modifier reads, when it
/// presents a panel. A change while a panel is up applies the next time one
/// is presented, as `allowedContentTypes` does.
struct FileDialogCustomization: Equatable {
    /// The text a panel shows above its folder, like a title.
    var message: String?

    /// The confirmation button's label.
    var confirmationLabel: String?

    /// The label of a save panel's name field (`fileExporterFilenameLabel(_:)`).
    var filenameLabel: String?

    /// The folder a panel opens on.
    var defaultDirectory: URL?

    /// How a panel presents the file system.
    var browserOptions: FileDialogBrowserOptions = []

    /// The test a URL must pass to be chosen.
    var urlEnabled: URLEnabled?

    /// Whether a chosen symbolic link is handed back as itself.
    var importsUnresolvedAliases = false

    /// The name a panel's state is kept under, across presentations and launches.
    var customizationID: String?

    /// Whether a panel shows its file-type pop-up
    /// (`fileDialogContentTypePicker(_:)`).
    var contentTypePicker: Visibility = .automatic

    /// Whether a panel says it browses another machine than the user's
    /// (`fileDialogRemoteNotice(_:)`).
    var remoteNotice: Visibility = .automatic

    /// A `fileDialogURLEnabled(_:)` predicate, by the identity of the box the
    /// modifier keeps it in: a `Predicate` cannot be compared, and an
    /// environment value that cannot be compared turns the memos beneath it
    /// off. The box is refreshed from each body, and a panel reads it only
    /// when it is presented, never while anything draws, so an identity that
    /// does not change says all a memo needs to know (as
    /// `SelectionContextMenu`'s closures are handed down).
    struct URLEnabled: Equatable {
        /// The box the modifier keeps.
        let box: Box

        /// The predicate the box holds now.
        var predicate: Predicate<URL> { box.predicate }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.box === rhs.box }

        /// The predicate a modifier's latest body gave it. Main-actor state:
        /// written by a body, read by a presentation.
        final class Box {
            var predicate: Predicate<URL>

            init(_ predicate: Predicate<URL>) {
                self.predicate = predicate
            }
        }
    }
}

private struct FileDialogCustomizationKey: EnvironmentKey {
    static var defaultValue: FileDialogCustomization { FileDialogCustomization() }
}

extension EnvironmentValues {
    /// What the `fileDialog` modifiers above have set.
    var fileDialogCustomization: FileDialogCustomization {
        get { self[FileDialogCustomizationKey.self] }
        set { self[FileDialogCustomizationKey.self] = newValue }
    }
}

// MARK: - The modifiers

extension View {
    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// with a custom text that is presented to the user, similar to a title.
    ///
    /// TUI's panels show it on every platform, as a line above the folder.
    ///
    /// - Parameter message: The optional text to use as the file dialog
    ///   message; `nil` shows none.
    nonisolated public func fileDialogMessage(_ message: Text?) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.message = message?.content }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// with a custom message that is presented to the user, similar to a
    /// title.
    ///
    /// - Parameter messageKey: The key to a localized string to display.
    nonisolated public func fileDialogMessage(_ messageKey: LocalizedStringKey) -> some View {
        let message = messageKey.localized
        return transformEnvironment(\.fileDialogCustomization) { $0.message = message }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// with a custom message that is presented to the user, similar to a
    /// title.
    ///
    /// - Parameter message: The string to use as the file dialog message.
    @_disfavoredOverload
    nonisolated public func fileDialogMessage<S: StringProtocol>(_ message: S) -> some View {
        let message = String(message)
        return transformEnvironment(\.fileDialogCustomization) { $0.message = message }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// with custom text as a confirmation button label.
    ///
    /// - Parameter label: The optional text to use as the label for the
    ///   confirmation button; `nil` keeps the panel's own (Open, Save, Move).
    nonisolated public func fileDialogConfirmationLabel(_ label: Text?) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.confirmationLabel = label?.content }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// with a custom confirmation button label.
    ///
    /// - Parameter labelKey: The key to a localized string to display.
    nonisolated public func fileDialogConfirmationLabel(_ labelKey: LocalizedStringKey) -> some View {
        let label = labelKey.localized
        return transformEnvironment(\.fileDialogCustomization) { $0.confirmationLabel = label }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// with a custom confirmation button label.
    ///
    /// - Parameter label: The string to use as the label for the confirmation
    ///   button.
    @_disfavoredOverload
    nonisolated public func fileDialogConfirmationLabel<S: StringProtocol>(_ label: S) -> some View {
        let label = String(label)
        return transformEnvironment(\.fileDialogCustomization) { $0.confirmationLabel = label }
    }

    /// Configures the `fileExporter`, `fileImporter`, or `fileMover` to open
    /// with the specified default directory.
    ///
    /// A panel with a `fileDialogCustomizationID(_:)` opens on the folder it
    /// was last left in once it has one, ignoring this, as SwiftUI documents.
    /// Without either, a TUI panel opens on the working directory, then on
    /// the folder of the last choice made through its modifier.
    ///
    /// - Parameter defaultDirectory: The directory to show when the file
    ///   dialog launches; `nil` for the panel's own choice.
    nonisolated public func fileDialogDefaultDirectory(_ defaultDirectory: URL?) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.defaultDirectory = defaultDirectory }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// to provide a refined URL search experience: include or exclude hidden
    /// files, allow searching by tag, etc.
    ///
    /// TUI's panels honour `.includeHiddenFiles` — the hidden-files switch
    /// starts on — and `.enumeratePackages` — a package (an `.app`) opens as
    /// the folder it is rather than being chosen as one file.
    /// `.displayFileExtensions` has no effect, as on macOS: a TUI panel
    /// shows every name whole.
    ///
    /// - Parameter options: The search options to apply to a given file dialog.
    nonisolated public func fileDialogBrowserOptions(_ options: FileDialogBrowserOptions) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.browserOptions = options }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// behavior when a user chooses an alias.
    ///
    /// By default a panel hands back the item a symbolic link the user chose
    /// leads to; `true` hands back the link itself. (A Finder alias file is a
    /// file of its own to a TUI panel, resolved or not.)
    ///
    /// - Parameter imports: A Boolean value that indicates if the application
    ///   receives unresolved or resolved URLs when a user chooses aliases.
    nonisolated public func fileDialogImportsUnresolvedAliases(_ imports: Bool) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.importsUnresolvedAliases = imports }
    }

    /// On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover`
    /// to persist and restore the file dialog configuration.
    ///
    /// A TUI panel with an identifier keeps the folder it was left in,
    /// whether it listed hidden files, and its view (list or columns), in the
    /// app's storage (the store
    /// `defaultAppStorage(_:)` names, else `StorageDefaults.backend`) under
    /// that identifier, and opens with them the next time — in this launch or
    /// a later one — in place of `fileDialogDefaultDirectory(_:)`'s folder.
    /// Without one, it opens on the default each launch.
    ///
    /// - Parameter id: An identifier of the configuration.
    nonisolated public func fileDialogCustomizationID(_ id: String) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.customizationID = id }
    }

    /// Shows or hides the file-type pop-up of the `fileImporter` or
    /// `fileExporter` panels beneath this view. A TUI-specific modifier:
    /// SwiftUI has no way to ask for the pop-up, which on macOS an app adds to
    /// an `NSOpenPanel` as an accessory view or turns on with `NSSavePanel`'s
    /// `showsContentTypes`.
    ///
    /// An open panel's pop-up, "Show:", narrows the files it lets the user
    /// choose to one of `allowedContentTypes`, or widens them to every file
    /// with All Files; the others are dimmed, as a type the panel does not
    /// take always is. A save panel's, "Format:", chooses which of
    /// `contentTypes` to save as, and gives the name that type's extension.
    ///
    /// ```swift
    /// .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { … }
    /// .fileDialogContentTypePicker(.visible)
    /// ```
    ///
    /// - Parameter visibility: `.automatic`, the default, shows it where a
    ///   panel has more than one type; `.visible` where it has any (so one
    ///   type and All Files); `.hidden` never. A panel that takes every type,
    ///   or chooses a folder, has none to show.
    nonisolated public func fileDialogContentTypePicker(_ visibility: Visibility) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.contentTypePicker = visibility }
    }

    /// Shows or hides the line the `fileImporter`, `fileExporter` and
    /// `fileMover` panels beneath this view show when they browse a machine
    /// other than the one the user is at. A TUI-specific modifier: a macOS
    /// panel always browses the Mac it is on, where a terminal app's panel
    /// browses the machine the app runs on, which over ssh is not the
    /// user's.
    ///
    /// The line, above the folder's path, reads "You are browsing the file
    /// system on *host*, not your local machine", after a warning sign, in
    /// the palette's warning colour, *host* being the name of the machine
    /// the app runs on.
    ///
    /// ```swift
    /// .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { … }
    /// .fileDialogRemoteNotice(.hidden)  // an app only ever run over ssh
    /// ```
    ///
    /// - Parameter visibility: `.automatic`, the default, shows it where
    ///   TUI has evidence that the user is at another machine: an ssh,
    ///   mosh or other remote session, or, inside tmux, an attached client
    ///   that is one. `.visible` shows it too where TUI cannot tell — a
    ///   session kept by GNU screen, zellij or another keeper whose clients
    ///   cannot be asked, which may be attached from anywhere — so the line
    ///   may then be wrong at the desk. `.hidden` never shows it.
    nonisolated public func fileDialogRemoteNotice(_ visibility: Visibility) -> some View {
        transformEnvironment(\.fileDialogCustomization) { $0.remoteNotice = visibility }
    }

    /// On macOS, configures the `fileImporter` or `fileMover` to conditionally
    /// disable presented URLs.
    ///
    /// An item whose URL the predicate refuses — or that it throws on — is
    /// drawn dimmed and cannot be chosen; a folder it refuses can still be
    /// opened. TUI evaluates it as it reads a folder, on another thread, so
    /// as Apple asks it should be quick and read nothing of the file.
    ///
    /// - Parameter predicate: The predicate that evaluates the URLs presented
    ///   to the user to conditionally disable them.
    nonisolated public func fileDialogURLEnabled(_ predicate: Predicate<URL>) -> some View {
        FileDialogURLEnabledModifier(content: self, predicate: predicate)
    }
}

/// `fileDialogURLEnabled(_:)`: the predicate kept in a box of this view's own,
/// so the environment value it writes compares equal from frame to frame
/// (``FileDialogCustomization/URLEnabled``).
private struct FileDialogURLEnabledModifier<Content: View> {
    let content: Content
    let predicate: Predicate<URL>

    /// The box: the first one made, kept for as long as this view lives.
    @State private var box: FileDialogCustomization.URLEnabled.Box

    init(content: Content, predicate: Predicate<URL>) {
        self.content = content
        self.predicate = predicate
        _box = State(initialValue: FileDialogCustomization.URLEnabled.Box(predicate))
    }

    @MainActor var body: some View {
        // The box's contents, not the state itself: nothing redraws for it.
        box.predicate = predicate
        let enabled = FileDialogCustomization.URLEnabled(box: box)
        return content.transformEnvironment(\.fileDialogCustomization) { $0.urlEnabled = enabled }
    }
}
extension FileDialogURLEnabledModifier: View {}
