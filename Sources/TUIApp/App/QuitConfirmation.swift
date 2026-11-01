//  🖥️ TUI — A Terminal UI framework for Swift
//  QuitConfirmation.swift
//
//  Which ways of quitting ask first, and the dialog that asks.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation
import TUIPresentation

// MARK: - Public API

/// When quitting asks first, with a dialog whose default answer is to stay.
///
/// Control-Q quits on its own word: it can't be pressed by habit in the hope of
/// something else. ⌃\\ can, since in a shell it ends the job in front, so by
/// default it asks. Both ask while a view drawn states a
/// `View.quitWarning(_:isActive:)`, and the dialog says what would be lost.
///
/// Control-C isn't a way of quitting. It's the copy key, and an app can bind it.
///
/// Set it on the scene, as ``Scene/quitConfirmation(_:)``.
///
/// TUI-specific. AppKit's nearest is the application delegate's
/// `applicationShouldTerminate(_:)`, which SwiftUI apps reach through an adaptor.
public enum QuitConfirmation: Sendable, Equatable {
    /// ⌃\\ asks; the quit key and the menu's Quit don't, unless a warning is
    /// active. The default.
    case automatic

    /// Everything asks: the quit key and the menu's Quit too. For an app where
    /// any quit is a loss, such as one holding a connection that can't be picked
    /// up again.
    case always

    /// Nothing asks unless a warning is active: ⌃\\ quits at once. For an app
    /// whose users know what that key does, and it then goes to the terminal
    /// driver, as in a shell, so it needs no reading by the app at all.
    case whenWarned
}

extension Scene {
    /// Sets when quitting asks first.
    ///
    /// ```swift
    /// WindowGroup { MailView() }
    ///     .quitConfirmation(.always)
    /// ```
    ///
    /// - Parameter confirmation: When quitting asks.
    /// - Returns: A scene whose quitting asks then.
    public func quitConfirmation(_ confirmation: QuitConfirmation) -> some Scene {
        _EnvironmentScene(content: self) { $0.quitConfirmation = confirmation }
    }
}

// MARK: - Environment

private struct QuitConfirmationKey: EnvironmentKey {
    static let defaultValue = QuitConfirmation.automatic
}

extension EnvironmentValues {
    /// When quitting asks first: the scene's ``Scene/quitConfirmation(_:)``, read
    /// by the run loop from the scene's root environment.
    var quitConfirmation: QuitConfirmation {
        get { self[QuitConfirmationKey.self] }
        set { self[QuitConfirmationKey.self] = newValue }
    }
}

// MARK: - The prompt

/// What asked to quit.
enum QuitRequest {
    /// The status bar's quit key (Control-Q by default), or the menu's Quit:
    /// keys that mean nothing but quitting.
    case quitKey

    /// The user's quit key, ⌃\\ (`Terminal.quitKeyByte`).
    case signalKey
}

/// Whether quitting asks first, what it says, and whether it is asking: what the
/// input chain, the run loop and the scene presenter share.
///
/// One per run, made by what runs the app. Not `Sendable`, as ``KeysAfterFrame``
/// is not: asked from key handlers and frames, all on the main actor.
final class QuitPrompt {
    /// When quitting asks: the scene's, adopted each frame.
    var confirmation = QuitConfirmation.automatic

    /// What the views drawn last frame say would be lost by quitting. A frame's
    /// worth out of date, as anything a key reads of the tree is.
    private(set) var warnings: [String] = []

    /// What the dialog's Quit does, while the dialog is up.
    private var proceed: (() -> Void)?

    /// The key that quits if pressed again while the dialog is up, if it was
    /// one of those that put it up, named as the dialog names it.
    private var pressAgainKey: String?

    /// Whether the scene presenter draws the dialog. It stays on once the dialog
    /// has been up: closing it takes a frame with the alert drawn and not
    /// presented, which hands the page its focus back.
    private(set) var isHosted = false

    /// Asks for a frame.
    private let requestFrame: () -> Void

    /// - Parameter requestFrame: Asks for a frame, to show or remove the dialog.
    init(requestFrame: @escaping () -> Void) {
        self.requestFrame = requestFrame
    }

    /// Whether the dialog is up.
    var isAsking: Bool { proceed != nil }

    /// Whether `request` asks before it quits: always with a warning active, and
    /// otherwise as the app's ``confirmation`` has it.
    func asks(before request: QuitRequest) -> Bool {
        guard warnings.isEmpty else { return true }
        switch (confirmation, request) {
        case (.always, _): return true
        case (.automatic, .signalKey): return true
        case (.automatic, .quitKey), (.whenWarned, _): return false
        }
    }

    /// Takes what the frame just drawn said, dropping repeats of the same words.
    func noteWarnings(_ stated: [String]) {
        var seen = Set<String>()
        let distinct = stated.filter { seen.insert($0).inserted }
        guard distinct != warnings else { return }
        warnings = distinct
        if isAsking { requestFrame() }
    }

    /// Puts the dialog up; its Quit runs `proceed`.
    ///
    /// - Parameters:
    ///   - pressAgainKey: The key that put it up and quits if pressed again
    ///     (⌃\\), for the dialog to say so; `nil` for the quit key, pressing
    ///     which again does nothing.
    ///   - proceed: What Quit does.
    func ask(pressAgainKey: String? = nil, then proceed: @escaping () -> Void) {
        self.pressAgainKey = pressAgainKey
        self.proceed = proceed
        isHosted = true
        requestFrame()
    }

    /// Takes the dialog down, without quitting.
    func dismiss() {
        proceed = nil
        requestFrame()
    }

    /// Takes the dialog down and quits.
    func confirm() {
        let proceed = proceed
        dismiss()
        proceed?()
    }

    /// The message the dialog shows: what would be lost, or else what quitting
    /// means, for a person who pressed ⌃\\ hoping to cancel something.
    var message: String {
        let service = LocalizationService.shared
        var message = service.string(for: LocalizationKey.Dialog.quitMessage)
        if !warnings.isEmpty {
            let list = warnings.map { "• " + $0 }.joined(separator: "\n")
            message = service.string(for: LocalizationKey.Dialog.quitInProgress) + "\n" + list
        }
        guard let pressAgainKey else { return message }
        let again = LocalizedStringKey.substituting(
            [pressAgainKey], into: service.string(for: LocalizationKey.Dialog.quitPressAgain))
        return message + "\n\n" + again
    }

    /// The dialog, as the scene presenter draws it over the window in front;
    /// `nil` until it has first been asked for.
    @MainActor var overlay: SceneOverlay? {
        guard isHosted else { return nil }
        return SceneOverlay(
            key: "quit-confirmation", configuration: SceneConfiguration(),
            view: AnyView(_QuitConfirmationDialog(prompt: self)))
    }
}

// MARK: - The dialog

/// The question: an alert, Cancel first, so the focus starts on it and Return
/// stays, as Escape does. Quit is a Tab away.
///
/// An alert and not a confirmation dialog: that kind has its destructive action
/// first and its Cancel last, so Return would quit.
struct _QuitConfirmationDialog: View {
    let prompt: QuitPrompt

    var body: some View {
        let prompt = prompt
        let service = LocalizationService.shared
        let appName = QuitPrompt.applicationName
        EmptyView()
            .alert(
                LocalizedStringKey.substituting([appName], into: service.string(for: LocalizationKey.Dialog.quitTitle)),
                isPresented: Binding(
                    get: { prompt.isAsking },
                    set: { if !$0, prompt.isAsking { prompt.dismiss() } })
            ) {
                Button(service.string(for: LocalizationKey.Button.cancel), role: .cancel) {}
                Button(service.string(for: LocalizationKey.Dialog.quitAction), role: .destructive) { prompt.confirm() }
            } message: {
                Text(verbatim: prompt.message)
            }
    }
}

extension QuitPrompt {
    /// The app's name, as a Mac would show it in the same question.
    fileprivate static var applicationName: String {
        let bundle = Bundle.main.infoDictionary
        return bundle?["CFBundleDisplayName"] as? String ?? bundle?["CFBundleName"] as? String
            ?? ProcessInfo.processInfo.processName
    }
}
