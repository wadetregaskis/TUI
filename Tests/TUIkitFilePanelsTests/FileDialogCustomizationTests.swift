//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FileDialogCustomizationTests.swift
//
//  The `fileDialog` modifiers, through the public `fileImporter`: each one's
//  effect on the panel it is written outside of.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFilePanels
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File dialog customizations", .serialized)
struct FileDialogCustomizationTests {
    /// An importer opening on `fixture`'s root, as an app writes one.
    private func importer(
        _ fixture: FilePanelFixture, caller: FilePanelCaller, types: [UTType] = [], multiple: Bool = false
    ) -> some View {
        Text("Page")
            .fileImporter(
                isPresented: caller.binding, allowedContentTypes: types, allowsMultipleSelection: multiple,
                onCompletion: { caller.completed($0) }, onCancellation: { caller.cancelled() }
            )
            .fileDialogDefaultDirectory(fixture.root)
    }

    @Test("The default directory is the folder the panel opens on")
    func defaultDirectory() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { importer(fixture, caller: caller) }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("beta.txt"))
        // Return on beta.txt, through the public importer's callback.
        driver.press(.down, times: 2)
        driver.press(.enter)
        #expect(caller.heard == ["chose (presented: false)"])
        #expect(caller.chosenPaths == [fixture.url("beta.txt").path])
    }

    @Test("The message and the confirmation label are the panel's")
    func messageAndLabel() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            importer(fixture, caller: caller)
                .fileDialogMessage("Choose the notes to merge")
                .fileDialogConfirmationLabel("Merge")
        }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("Choose the notes to merge"))
        // The title stays the panel's own; the button is renamed.
        #expect(shown.contains("( Merge )"))
        #expect(!shown.contains("( Open )"))
    }

    @Test("A Text message and label read as their words")
    func textForms() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            importer(fixture, caller: caller)
                .fileDialogMessage(Text(verbatim: "Pick one"))
                .fileDialogConfirmationLabel(Text(verbatim: "Use"))
        }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains("Pick one") && shown.contains("Use"))
    }

    @Test("Including hidden files starts the switch on")
    func includeHiddenFiles() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            importer(fixture, caller: caller).fileDialogBrowserOptions(.includeHiddenFiles)
        }
        let shown = await driver.waitFor("notes.md")
        #expect(shown.contains(".hidden"))
    }

    @Test("A URL the predicate refuses cannot be chosen")
    func urlEnabled() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let refused = fixture.url("beta.txt").lastPathComponent
        let driver = FilePanelDriver {
            importer(fixture, caller: caller)
                .fileDialogURLEnabled(#Predicate<URL> { $0.lastPathComponent != refused })
        }
        await driver.waitFor("notes.md")
        // Alpha/, linked/, then beta.txt — refused: Return chooses nothing —
        // and gamma.pdf.
        driver.press(.down, times: 2)
        driver.press(.enter)
        #expect(caller.heard.isEmpty)
        driver.press(.down)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("gamma.pdf").path])
    }

    @Test("Importing unresolved aliases hands back the link itself")
    func unresolvedAliases() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver {
            importer(fixture, caller: caller, types: [.folder]).fileDialogImportsUnresolvedAliases(true)
        }
        await driver.waitFor("notes.md")
        driver.press(.down)
        driver.press(.space)
        driver.press(.tab, times: 3)
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("linked").path])
    }

    @Test("A customization ID keeps the folder the panel was left in, over the default")
    func customizationID() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let store = MockStorageBackend()
        let driver = FilePanelDriver {
            importer(fixture, caller: caller)
                .fileDialogCustomizationID("notes")
                .defaultAppStorage(store)
        }
        await driver.waitFor("notes.md")
        driver.press(.enter)
        await driver.waitFor("inner.txt")
        driver.press(.escape)
        #expect(caller.heard == ["cancelled (presented: false)"])
        let keys = FilePanelPresenter<EmptyView>.storageKeys("notes")
        #expect(store.entry(forKey: keys.directory, as: String.self).value == fixture.url("Alpha").path)
        // Presented again, it opens in Alpha, not on the default directory.
        caller.isPresented = true
        let again = await driver.waitFor("inner.txt", timeout: .seconds(5))
        #expect(again.contains("inner.txt") && !again.contains("beta.txt"), "\(again)")
    }

    #if canImport(Darwin)
        @Test("A package is one file, unless packages are enumerated")
        func packages() async throws {
            let fixture = try FilePanelFixture()
            defer { fixture.remove() }
            try FileManager.default.createDirectory(
                at: fixture.url("Tool.app/Contents"), withIntermediateDirectories: true)
            let flat = try DirectoryListing.read(fixture.root, rule: FileChoiceRule()).get()
            #expect(flat.first { $0.name == "Tool.app" }?.isFolder == false)
            let opened = try DirectoryListing.read(fixture.root, rule: FileChoiceRule(enumeratesPackages: true)).get()
            #expect(opened.first { $0.name == "Tool.app" }?.isFolder == true)
            // The modifier sets it.
            var request = FilePanelRequest(
                purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "", confirmationLabel: "",
                startDirectory: fixture.root)
            var customization = FileDialogCustomization()
            customization.browserOptions = [.enumeratePackages]
            FilePanelPresenter<EmptyView>.apply(customization, to: &request)
            #expect(request.rule.enumeratesPackages)
        }
    #endif
}
