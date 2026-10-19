//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelsPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

// MARK: - File Panels Page

/// The file panels: SwiftUI's `fileImporter`, `fileExporter` and `fileMover`,
/// presented as the open and save panels TUIkit draws, with what each handed
/// back. Every panel here browses the real file system, from the folder the
/// Example was started in.
struct FilePanelsPage: View {
    @State private var opening = false
    @State private var openingSeveral = false
    @State private var choosingFolder = false
    @State private var saving = false
    @State private var moving = false

    /// What the last panel handed back, or why it did not.
    @State private var outcome = ""

    /// The note the save panel saves.
    @State private var note = L("page.files.noteText")

    /// The file the mover moves: made on demand, in the temporary folder.
    @State private var fileToMove: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("page.files.intro").foregroundStyle(.palette.foregroundSecondary)
            open
            save
            move
            ValueDisplayRow("page.files.outcome", outcome.isEmpty ? L("page.files.nothingYet") : outcome)
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

    // MARK: - Open

    private var open: some View {
        DemoSection("page.files.openSection") {
            HStack(spacing: 2) {
                Button("page.files.open") { opening = true }
                    .fileImporter(isPresented: $opening, allowedContentTypes: []) { result in
                        report(result.map { [$0] })
                    }
                    .fileDialogMessage("page.files.openMessage")
                Button("page.files.openSeveral") { openingSeveral = true }
                    .fileImporter(
                        isPresented: $openingSeveral, allowedContentTypes: [.plainText, .sourceCode, .json],
                        allowsMultipleSelection: true
                    ) { result in
                        report(result)
                    } onCancellation: {
                        outcome = L("page.files.cancelled")
                    }
                    .fileDialogConfirmationLabel("page.files.openSeveralLabel")
                Button("page.files.chooseFolder") { choosingFolder = true }
                    .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                        report(result.map { [$0] })
                    }
                    .fileDialogBrowserOptions(.includeHiddenFiles)
            }
        }
    }

    // MARK: - Save

    @ViewBuilder private var save: some View {
        DemoSection("page.files.saveSection") {
            HStack(spacing: 2) {
                TextField("page.files.noteLabel", text: $note)
                    .frame(width: 30)
                #if canImport(CoreTransferable)
                    Button("page.files.save") { saving = true }
                        .fileExporter(
                            isPresented: $saving, item: note, contentTypes: [.plainText],
                            defaultFilename: L("page.files.noteName")
                        ) { result in
                            report(result.map { [$0] })
                        }
                        .fileExporterFilenameLabel("page.files.saveAsLabel")
                #else
                    Text("page.files.saveUnavailable").foregroundStyle(.palette.foregroundSecondary)
                #endif
            }
        }
    }

    // MARK: - Move

    private var move: some View {
        DemoSection("page.files.moveSection") {
            HStack(spacing: 2) {
                Button("page.files.makeFile") { makeFileToMove() }
                Button("page.files.move") { moving = true }
                    .disabled(fileToMove == nil)
                    .fileMover(isPresented: $moving, file: fileToMove) { result in
                        if case .success(let url) = result { fileToMove = url }
                        report(result.map { [$0] })
                    }
                Text(fileToMove.map { $0.path } ?? L("page.files.noFile"))
                    .foregroundStyle(.palette.foregroundSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
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
            outcome = "\(L("page.files.failed")): \(error.localizedDescription)"
        }
    }

    // MARK: - What came back

    private func report(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            outcome = urls.map(\.path).joined(separator: ", ")
        case .failure(let error):
            outcome = "\(L("page.files.failed")): \(error.localizedDescription)"
        }
    }
}
