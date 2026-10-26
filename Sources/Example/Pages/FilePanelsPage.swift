//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelsPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

// MARK: - File Panels Page

/// The file panels: SwiftUI's `fileImporter`, `fileExporter` and `fileMover`,
/// presented as the open and save panels TUI draws, with what each handed
/// back: beside each button, its panel's result (the paths chosen, where it
/// saved, or "Cancelled"), cleared to "—" as the panel opens. Every panel here
/// browses the real file system, from the folder the Example was started in.
struct FilePanelsPage: View {
    @State private var opening = false
    @State private var openingSeveral = false
    @State private var choosingFolder = false
    @State private var saving = false
    @State private var moving = false

    /// The panels this page presents, each with a result of its own.
    private enum Dialog: Hashable {
        case open, several, folder, save, move
    }

    /// What each panel last handed back, or why it did not; a panel not in it
    /// has handed back nothing since it opened.
    @State private var results: [Dialog: String] = [:]

    /// The note the save panel saves.
    @State private var note = L("page.files.noteText")

    /// The file the mover moves: made on demand, in the temporary folder.
    @State private var fileToMove: URL?

    /// Whether the panels are told this is a remote session, so that they
    /// show the notice an ssh session gets: "You are browsing the file
    /// system on <host>, not your local machine". A demo's pin of the
    /// judgement the panels make themselves (`filePanelSession`, package
    /// API, not an app's).
    @State private var simulatingRemote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("page.files.intro").foregroundStyle(.palette.foregroundSecondary)
            Toggle("page.files.simulateRemote", isOn: $simulatingRemote)
            Group {
                open
                save
                move
            }
            .environment(\.filePanelSession, simulatedSession)
            KeyboardHelpSection(
                "page.files.keys",
                shortcuts: [
                    "page.files.help.return",
                    "page.files.help.space",
                    "page.files.help.up",
                    "page.files.help.escape",
                ]
            )
            Spacer()
        }
        .scrollableDemoPage()
        .navigationTitle("menu.item.files")
    }

    /// The session the panels are judged on: a remote one on this machine's
    /// name (`gethostname`'s, read once, as a panel reads it) while the
    /// toggle is on, else `nil`, the process's own.
    private var simulatedSession: FilePanelSession? {
        guard simulatingRemote else { return nil }
        return FilePanelSession(judgement: .remote, hostName: TerminalClient.localHostName ?? "localhost")
    }

    // MARK: - Open

    private var open: some View {
        DemoSection("page.files.openSection") {
            VStack(alignment: .leading, spacing: 0) {
                row(.open) {
                    Button("page.files.open") { present(.open, $opening) }
                        .fileImporter(
                            isPresented: $opening, allowedContentTypes: [], allowsMultipleSelection: false,
                            onCompletion: { report($0, of: .open) }, onCancellation: { cancelled(.open) }
                        )
                        .fileDialogMessage("page.files.openMessage")
                }
                row(.several) {
                    Button("page.files.openSeveral") { present(.several, $openingSeveral) }
                        .fileImporter(
                            isPresented: $openingSeveral, allowedContentTypes: [.plainText, .sourceCode, .json],
                            allowsMultipleSelection: true,
                            onCompletion: { report($0, of: .several) }, onCancellation: { cancelled(.several) }
                        )
                        .fileDialogConfirmationLabel("page.files.openSeveralLabel")
                }
                row(.folder) {
                    Button("page.files.chooseFolder") { present(.folder, $choosingFolder) }
                        .fileImporter(
                            isPresented: $choosingFolder, allowedContentTypes: [.folder],
                            allowsMultipleSelection: false,
                            onCompletion: { report($0, of: .folder) }, onCancellation: { cancelled(.folder) }
                        )
                        .fileDialogBrowserOptions(.includeHiddenFiles)
                }
            }
        }
    }

    // MARK: - Save

    @ViewBuilder private var save: some View {
        DemoSection("page.files.saveSection") {
            VStack(alignment: .leading, spacing: 0) {
                TextField("page.files.noteLabel", text: $note)
                    .frame(width: 30)
                #if canImport(CoreTransferable)
                    row(.save) {
                        Button("page.files.save") { present(.save, $saving) }
                            .fileExporter(
                                isPresented: $saving, item: note, contentTypes: [.plainText],
                                defaultFilename: L("page.files.noteName"),
                                onCompletion: { report($0.map { [$0] }, of: .save) },
                                onCancellation: { cancelled(.save) }
                            )
                            .fileExporterFilenameLabel("page.files.saveAsLabel")
                    }
                #else
                    Text("page.files.saveUnavailable").foregroundStyle(.palette.foregroundSecondary)
                #endif
            }
        }
    }

    // MARK: - Move

    private var move: some View {
        DemoSection("page.files.moveSection") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    Button("page.files.makeFile") { makeFileToMove() }
                    Text(fileToMove.map { $0.path } ?? L("page.files.noFile"))
                        .foregroundStyle(.palette.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                row(.move) {
                    Button("page.files.move") { present(.move, $moving) }
                        .disabled(fileToMove == nil)
                        .fileMover(
                            isPresented: $moving, file: fileToMove,
                            onCompletion: { result in
                                if case .success(let url) = result { fileToMove = url }
                                report(result.map { [$0] }, of: .move)
                            }, onCancellation: { cancelled(.move) })
                }
            }
        }
    }

    /// Makes a small text file in the temporary folder, for the mover.
    private func makeFileToMove() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(L("page.files.moveFileName")) \(Int.random(in: 1000...9999)).txt")
        do {
            try Data(note.utf8).write(to: url)
            fileToMove = url
        } catch {
            results[.move] = "\(L("page.files.failed")): \(error.localizedDescription)"
        }
    }

    // MARK: - What came back

    /// A panel's button, and beside it what the panel last handed back.
    private func row(_ dialog: Dialog, @ViewBuilder button: () -> some View) -> some View {
        HStack(spacing: 2) {
            button()
            ValueDisplayRow("page.files.result", results[dialog] ?? "—")
        }
    }

    /// Opens a panel, clearing its result first so that choosing the same
    /// thing twice reads as two results.
    private func present(_ dialog: Dialog, _ flag: Binding<Bool>) {
        results[dialog] = "—"
        flag.wrappedValue = true
    }

    private func cancelled(_ dialog: Dialog) {
        results[dialog] = L("page.files.cancelled")
    }

    private func report(_ result: Result<[URL], any Error>, of dialog: Dialog) {
        switch result {
        case .success(let urls):
            results[dialog] = urls.map(\.path).joined(separator: ", ")
        case .failure(let error):
            results[dialog] = "\(L("page.files.failed")): \(error.localizedDescription)"
        }
    }
}
