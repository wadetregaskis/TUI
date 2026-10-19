//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AmbientApp.swift
//
//  The app whose work is under way, for code that changes what an app draws
//  but was handed no way to reach the app.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - App Render State

/// An app's render state as code anywhere in TUIkit sees it: what it can ask
/// of the app whose work is under way (``AmbientApp/renderState``).
///
/// `AppState` is the one conformer. A protocol, down here, only so that code
/// in every module can reach it — the render state itself lives with the
/// views.
package protocol AppRenderState: AnyObject, Sendable {
    /// Asks the app for a frame, under the transaction in force
    /// (``Transaction/ambient``) if there is one.
    func setNeedsRender()

    /// Asks the app for a frame drawn with an empty render cache.
    func setNeedsRenderWithCacheClear()

    /// Asks the app's run loop to exit.
    func requestExit()

    /// A ``withTransaction(_:_:)`` scope run in the app's work has ended, with
    /// `transaction` in force for whatever it changed: the app may take it for
    /// a change whose own report carried none.
    func transactionScopeEnded(_ transaction: Transaction)
}

// MARK: - Ambient App

/// The app whose work is under way where ``renderState`` is read.
///
/// Every app has its own render state — two apps in one process, as parallel
/// tests have, must never take each other's frames or transactions — and
/// almost everything that asks for a frame holds its app's: a `@State` box
/// through its render cache's link, an observed body through the same link,
/// the run loop's own seams through the context. What holds nothing is code an
/// app runs that changes something every view of it may read, with no view in
/// hand: an `@AppStorage` write, a change of language, a top-level `dismiss()`
/// with no environment behind it. Those ask the app whose work they are part
/// of: its event handlers, its frames, and the tasks they start. So does a
/// ``withTransaction(_:_:)`` scope as it ends, for an observed change whose
/// observation an earlier write had already fired.
///
/// A task local, not a global: it is bound for the duration of an app's work —
/// by `AppRunner` around its run loop, by `HeadlessApp` around each frame and
/// each event — so it is per task, nests, and is inherited by a `Task` made
/// inside it, as a `.task` modifier's is. Work on no app's task — a callback a
/// framework calls on a queue of its own — finds `nil`, and asks no app for a
/// frame; the views that read what it changed still hear of it, through the
/// observation that reaches their own app. A change of language, or of the
/// strings an app registered, is the localization service's, which no
/// observation reports: it also asks every app running from the service,
/// which each app's run loop notes there, so it reaches the screen from
/// there too.
package enum AmbientApp {
    /// The render state of the app whose work is under way, or `nil` outside
    /// every app's.
    @TaskLocal package static var renderState: (any AppRenderState)?
}
