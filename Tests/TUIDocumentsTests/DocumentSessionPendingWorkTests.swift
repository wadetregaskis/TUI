//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentSessionPendingWorkTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIDocuments

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// What waits on the save panel is told when something else takes the panel
/// over: an `openDocument(at:)` waiting on it was otherwise never resumed, and
/// its `await` never returned.
@MainActor
@Suite("Document session: work waiting on the save panel")
struct DocumentSessionPendingWorkTests {

    /// An untitled document that is never written anywhere.
    private final class Store: DocumentStore {
        var readableContentTypes: [UTType] { [.plainText] }
        var writableContentTypes: [UTType] { [.plainText] }
        var hasDocument: Bool { true }
        var canMakeNew: Bool { true }
        func makeNew() {}
        func load(from url: URL, as type: UTType) async throws {}
        func save(to url: URL, as type: UTType, existing: URL?) async -> Result<URL, any Error> { .success(url) }
        func watchForEdits(contentType: UTType, _ edited: @escaping @MainActor @Sendable () -> Void) {}
        func configuration(in session: DocumentSession) -> Any? { nil }
    }

    /// An edited, untitled session whose question about the changes has been
    /// answered Save, so `work` waits on the save panel; and what `work` was told.
    private func waitingOnThePanel() -> (DocumentSession, outcome: () -> String) {
        let session = DocumentSession(store: Store(), isViewer: false)
        session.noteEdit()
        var outcome = "waiting"
        session.pastChanges(.init(run: { outcome = "ran" }, abandoned: { outcome = "abandoned" }))
        session.answerSave()
        #expect(session.isSavePanelShown)
        return (session, { outcome })
    }

    @Test("Save As over a save waiting on the panel abandons what waited")
    func saveAsAbandonsTheWaitingWork() {
        let (session, outcome) = waitingOnThePanel()
        session.saveAs()
        #expect(outcome() == "abandoned")
    }

    @Test("A second question answered Save abandons the work the first left waiting on the panel")
    func secondSaveAbandonsTheFirst() {
        let (session, outcome) = waitingOnThePanel()
        var second = "waiting"
        session.pastChanges(.init(run: { second = "ran" }, abandoned: { second = "abandoned" }))
        session.answerSave()
        #expect(outcome() == "abandoned")
        #expect(second == "waiting")
        session.savePanelCancelled()
        #expect(second == "abandoned")
    }
}
