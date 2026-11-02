//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentWindow.swift
//
//  What a `DocumentGroup`'s window draws: the app's editor or viewer, with the
//  panels and the questions around it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFilePanels
import TUIFoundation
import TUIPresentation
import TUIView

/// Keeps a window's session for the life of the window: a reference, made empty
/// wherever the view is, so `newDocument` runs once and not once per declaration
/// (a `@State`'s initial value is made every time its view is).
@MainActor
final class DocumentWindowKeeper {
    nonisolated init() {}

    /// The session, made by the first frame that asks for it.
    private var session: DocumentSession?

    /// The content's `\.dismiss`, kept so the action is equal from frame to
    /// frame, as `PendingDismissal`'s is.
    private(set) lazy var contentDismissal = DismissAction.Box()

    /// The session, made with `make` the first time.
    func session(make: () -> DocumentSession) -> DocumentSession {
        if let session { return session }
        let made = make()
        session = made
        return made
    }
}

/// The app's editor or viewer, the panels that open and save, and the questions
/// about unsaved changes and failures.
struct DocumentWindow<Content: View>: View {
    let makeStore: @MainActor @Sendable () -> any DocumentStore
    let isViewer: Bool
    let content: (Any) -> Content?

    @State private var keeper = DocumentWindowKeeper()

    /// What `dismiss()` means outside the window: quitting.
    @Environment(\.dismiss) private var outerDismiss

    var body: some View {
        let session = keeper.session { DocumentSession(store: makeStore(), isViewer: isViewer) }
        // The quit key's question goes outside the dialog's presenter, which
        // draws what it covers as an inert backdrop: registered from in there, a
        // quit key that works under a dialog would lose the question while it
        // was up, as `dismissalConfirmationDialog`'s would.
        return
            panels(page(session), session)
            // A confirmation dialog, as `dismissalConfirmationDialog`'s question
            // is: an alert draws Cancel first and starts the focus there, which
            // would make Return lose the question's answer on macOS, Save.
            .confirmationDialog(
                LocalizationService.shared.string(for: LocalizationKey.Document.unsavedChanges),
                isPresented: Self.binding(session, \.isAskingToSave),
                titleVisibility: .visible
            ) {
                unsavedActions(session)
            } message: {
                Text(Self.unsavedMessage(session))
            }
            .alert(
                session.failure?.title ?? "",
                isPresented: Binding(
                    get: { session.failure != nil },
                    set: { if !$0 { session.failure = nil } })
            ) {
                Button(LocalizationService.shared.string(for: LocalizationKey.Button.ok)) {}
            } message: {
                Text(session.failure?.message ?? "")
            }
            .askingBeforeDismissal(when: session.isEdited) { proceed in
                session.pastChanges(DocumentSession.PendingWork(run: proceed))
            }
    }

    /// What is drawn beneath the panels: the app's content, once there is a
    /// document, knowing it is in this window.
    private func page(_ session: DocumentSession) -> some View {
        let outer = outerDismiss
        let dismissal = keeper.contentDismissal
        dismissal.action = {
            // The app's own `dismiss()` asks, as a dismissal confirmation's does.
            session.pastChanges(DocumentSession.PendingWork(run: { outer() }))
        }
        return Group {
            if let configuration = session.store.configuration(in: session), let view = content(configuration) {
                view.id(session.documentNumber)
            } else {
                noDocument(session)
            }
        }
        .environment(\.documentConfiguration, session.configuration)
        .environment(\.newDocument, NewDocumentAction(session: session))
        .environment(\.openDocument, OpenDocumentAction(session: session))
        .environment(\.dismiss, DismissAction(box: dismissal))
        .navigationTitle(session.title)
        .focusedSceneValue(\.documentSession, session)
    }

    /// A viewer's page once the open panel has been cancelled: a word, and a way
    /// back to it that does not need the menu bar.
    private func noDocument(_ session: DocumentSession) -> some View {
        VStack(spacing: 1) {
            Text(LocalizationService.shared.string(for: LocalizationKey.Document.none))
            Button(LocalizationService.shared.string(for: LocalizationKey.Document.open)) { session.open() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `page` with the open and save panels on it, opening where the last file
    /// was, when there has been one.
    private func panels(_ page: some View, _ session: DocumentSession) -> some View {
        page
            .fileImporter(
                isPresented: Self.binding(session, \.isOpenPanelShown),
                allowedContentTypes: session.store.readableContentTypes
            ) { result in
                if case .success(let url) = result {
                    session.open(chosen: url)
                }
            }
            .documentSavePanel(
                isPresented: Self.binding(session, \.isSavePanelShown),
                contentTypes: session.store.writableContentTypes,
                defaultFilename: session.nameToSaveAs,
                onChoose: { session.savePanelChose($0) },
                onCancel: { session.savePanelCancelled() }
            )
            .documentPanelFolder(session.lastFolder)
    }

    /// The question, about this document, and what is at stake.
    private static func unsavedMessage(_ session: DocumentSession) -> String {
        let service = LocalizationService.shared
        let question = LocalizedStringKey.substituting(
            [session.name], into: service.string(for: LocalizationKey.Document.saveChanges))
        return "\(question)\n\(service.string(for: LocalizationKey.Document.changesLost))"
    }

    /// The question's answers, Save first and so on Return, as on macOS.
    @ViewBuilder
    private func unsavedActions(_ session: DocumentSession) -> some View {
        Button(LocalizationService.shared.string(for: LocalizationKey.Button.save)) { session.answerSave() }
        Button(LocalizationService.shared.string(for: LocalizationKey.Document.dontSave), role: .destructive) {
            session.answerDontSave()
        }
        Button(LocalizationService.shared.string(for: LocalizationKey.Button.cancel), role: .cancel) {
            session.answerCancel()
        }
    }

    /// A binding to one of `session`'s flags.
    private static func binding(
        _ session: DocumentSession, _ flag: ReferenceWritableKeyPath<DocumentSession, Bool>
    ) -> Binding<Bool> {
        Binding(get: { session[keyPath: flag] }, set: { session[keyPath: flag] = $0 })
    }
}
