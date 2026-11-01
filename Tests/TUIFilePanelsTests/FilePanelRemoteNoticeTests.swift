//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelRemoteNoticeTests.swift
//
//  The line a file panel shows when it browses a machine the user is not at:
//  when it shows, what it says, its sign, and where it sits.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
@testable import TUIStrings
@testable import TUITestSupport

/// Serialized for the reason ``FileImporterPanelTests`` is.
@MainActor
@Suite("File panel remote-machine notice", .serialized)
struct FilePanelRemoteNoticeTests {
    static let sentence = "You are browsing the file system on build-box, not your local machine."

    @Test("Automatic names the machine only on evidence; visible where it is not known to be here; hidden never")
    func visibility() {
        func notice(_ judgement: SessionLocality.Judgement, _ visibility: Visibility) -> String? {
            FilePanelSession(judgement: judgement, hostName: "build-box").notice(visibility)
        }
        #expect(notice(.remote, .automatic) == "build-box")
        #expect(notice(.unknown, .automatic) == nil)
        #expect(notice(.local, .automatic) == nil)
        #expect(notice(.remote, .visible) == "build-box")
        #expect(notice(.unknown, .visible) == "build-box")
        #expect(notice(.local, .visible) == nil)
        #expect(notice(.remote, .hidden) == nil)
    }

    /// A panel over `fixture`'s root, judged on `session`.
    private func panel(
        _ fixture: FilePanelFixture, caller: FilePanelCaller, session: SessionLocality.Judgement,
        emoji: Bool = false, visibility: Visibility = .automatic, hostName: String = "build-box"
    ) -> some View {
        FilePanelPresenter(
            content: Text("Page"), isPresented: caller.binding,
            request: {
                FilePanelRequest(
                    purpose: .open(allowsMultipleSelection: false), rule: FileChoiceRule(), title: "Open",
                    confirmationLabel: "Open", startDirectory: fixture.root, homeDirectory: fixture.root)
            },
            onChoose: { caller.chose($0) }, onCancel: { caller.cancelled() }
        )
        .fileDialogRemoteNotice(visibility)
        .environment(\.supportsEmojiChrome, emoji)
        .environment(\.filePanelSession, FilePanelSession(judgement: session, hostName: hostName))
    }

    @Test("Browsing another machine, the panel says so on the line above the path, after a bold !")
    func remote() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, session: .remote) }
        let shown = await driver.waitFor(Self.sentence)
        #expect(shown.contains("! " + Self.sentence), "\(shown)")
        #expect(!shown.contains("\u{26A0}"))
        // On the path, with no row between, though the default control size
        // sets the panel's parts a row apart.
        let notice = try #require(driver.position(of: Self.sentence))
        let path = try #require(driver.position(of: "↰"))
        #expect(path.y == notice.y + 1, "\(shown)")
        // The keys are the panel's still: the notice takes no focus.
        await driver.waitFor("notes.md")
        driver.press(.character("g"))
        driver.press(.enter)
        #expect(caller.chosenPaths == [fixture.url("gamma.pdf").path])
    }

    /// A cloud machine's name is often this long. It filled the line, and "not
    /// your local machine", the words that say what the notice means, were cut off.
    @Test("A long machine name wraps the sentence, and keeps all of it")
    func longMachineName() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let host = "iad20-fj924-989f5eb8-1b39-4289-816c-d54e8ad40c21"
        let driver = FilePanelDriver { panel(fixture, caller: caller, session: .remote, hostName: host) }
        let shown = await driver.waitFor("your local machine.")
        #expect(shown.contains(host), "\(shown)")
    }

    @Test("Where emoji chrome draws, the sign is the alert's ⚠️")
    func emojiSign() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        let caller = FilePanelCaller()
        let driver = FilePanelDriver { panel(fixture, caller: caller, session: .remote, emoji: true) }
        let shown = await driver.waitFor(Self.sentence)
        #expect(shown.contains("\u{26A0}\u{FE0F} " + Self.sentence), "\(shown)")
    }

    @Test("At the desk, or where TUI cannot tell, there is no notice; .visible shows it where it cannot tell")
    func noNotice() async throws {
        let fixture = try FilePanelFixture()
        defer { fixture.remove() }
        for (session, visibility, shows) in [
            (SessionLocality.Judgement.local, Visibility.automatic, false), (.unknown, .automatic, false),
            (.unknown, .visible, true), (.remote, .hidden, false),
        ] {
            let caller = FilePanelCaller()
            let driver = FilePanelDriver {
                panel(fixture, caller: caller, session: session, visibility: visibility)
            }
            // The folder is read, and the session judged, as the panel opens.
            let shown = await driver.waitFor(shows ? Self.sentence : "notes.md")
            #expect(shown.contains(Self.sentence) == shows, "\(session), \(visibility): \(shown)")
        }
    }

    @Test("The sentence is translated, the machine's name in its place")
    func translated() {
        let key = LocalizationKey.FilePanel.remoteNotice.rawValue
        let english = LocalizationService.shared.string(for: key, in: .english)
        #expect(english == Self.sentence.replacingOccurrences(of: "build-box", with: "%@"))
        for language in LocalizationService.Language.allCases where language != .english {
            let format = LocalizationService.shared.string(for: key, in: language)
            #expect(format.components(separatedBy: "%@").count == 2, "\(language): \(format)")
            #expect(format != english, "\(language)")
        }
    }
}
