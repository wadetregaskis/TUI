//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentClip.swift
//
//  `document`: a postcard app, and a document's life in TUI's file panels,
//  from the keyboard. An untitled postcard is given a picture through the
//  open panel, filtered to images, in its column view, each picture selected
//  previewed beside it — found by typing its name; a message is typed, and
//  the title says it is edited. Saved: the name offered, a folder picked in
//  the save panel's list. Edited again and closed, it asks whether to save;
//  not saved, it is opened again through the open panel, filtered to
//  postcards, each previewed; exported as Markdown through the Format pop-up;
//  and a new postcard is where the loop began.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI
import UniformTypeIdentifiers

@MainActor
let documentClip = Clip(
    id: "document",
    title: "Documents",
    // Ghostty rounds the window up a cell or two: asked for 110 × 31, it
    // draws 112 × 32, the grid the camera frames whole.
    columns: 110,
    rows: 31,
    output: 800,
    // Photographs: WebP blocks them at the default quality.
    quality: 88,
    budgetKB: 800,
    script: documentScript(),
    environment: ["CFFIXED_USER_HOME": PostcardHome.root.path],
    run: {
        PostcardHome.make()
        await PostcardApp.main()
    }
)

/// An app chord, captioned in the toolbar a moment before it is pressed:
/// what was pressed and what it does, for a viewer who cannot see the keys.
private func chord(_ keys: Step, _ caption: String) -> [Step] {
    [.cue("key \(caption)"), .wait(0.5), keys]
}

private func documentScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 0, width: 112, height: 32)), .wait(1.0)]
    // Add Picture… has the focus: the open panel, filtered to images, in its
    // column view on ~/Pictures. The picture selected is previewed; typing
    // "bu" finds the burrowing owl, Space previews it, Return chooses it.
    script += [.space, .wait(1.1), .space, .wait(1.2)]
    script += Step.type("bu", interval: 0.15) + [.wait(0.35), .space, .wait(1.3), .enter, .wait(0.8)]
    // The message, typed: the title says the postcard is edited.
    script += Step.type("Greetings from the burrow!", interval: 0.055) + [.enter]
    script += Step.type("Ollie says hi.", interval: 0.055) + [.wait(0.6)]
    // Saved: the name the picture gave it offered, a folder picked in the
    // save panel's list — past the path and the view switcher, down to it,
    // opened — and saved there, from the Save button. (Arrows, not typing:
    // typing finds no folder in the list view; see the commit message.)
    script += chord(Step.control("s"), "⌃S  Save") + [.wait(1.2)]
    script += Step.repeat(.tab, 3, interval: 0.25) + [.wait(0.2)]
    script += Step.repeat(.down, 6, interval: 0.2) + [.wait(0.4), .enter, .wait(0.9)]
    script += Step.repeat(.tab, 3, interval: 0.25) + [.wait(0.2), .space, .wait(0.9), .cue("clear")]
    // Edited again, and closed from the File menu: it asks; not saved.
    script += Step.type(" See you soon!", interval: 0.055) + [.wait(0.4)]
    script += [.f10, .wait(0.5), .right, .wait(0.5)] + Step.repeat(.down, 3, interval: 0.25)
    // The question's keys start on Cancel; Don't Save is two along.
    script += [.wait(0.3), .enter, .wait(1.3), .tab, .wait(0.4), .tab, .wait(0.5), .enter, .wait(0.9)]
    // Opened again, filtered to postcards, each previewed: its picture and
    // its message.
    script += chord(Step.control("o"), "⌃O  Open…") + [.wait(1.0)]
    script += [.space, .wait(1.2), .down, .wait(0.3), .space, .wait(1.2), .up, .wait(0.3), .space, .wait(0.7)]
    script += [.enter, .wait(0.5), .cue("clear"), .wait(0.5)]
    // Exported as Markdown, from the File menu: the Format pop-up renames
    // the file.
    script += [.f10, .wait(0.5), .right, .wait(0.5)] + Step.repeat(.down, 5, interval: 0.2)
    script += [.wait(0.3), .enter, .wait(1.2)]
    script += Step.repeat(.tab, 4, interval: 0.25) + [.wait(0.2), .space, .wait(0.6), .down, .wait(0.5), .enter]
    script += [.wait(0.9)] + Step.repeat(.tab, 3, interval: 0.25) + [.wait(0.2), .space, .wait(1.6)]
    // A new postcard: where the loop began.
    script += chord(Step.control("n"), "⌃N  New") + [.wait(0.7), .cue("clear"), .wait(0.8)]
    return script
}

struct PostcardApp: App {
    @State private var desk = PostcardDesk()

    var body: some Scene {
        WindowGroup("TUI · Postcards") {
            PostcardWindow(desk: desk)
                .palette(SystemPalette(.blue))
                .task {
                    for await cue in ClipCues.stream() {
                        withAnimation(.easeOut(duration: 0.15)) {
                            desk.caption = cue.hasPrefix("key ") ? String(cue.dropFirst(4)) : nil
                        }
                    }
                }
        }
        .aboutPanel(applicationName: "Postcards")
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Postcard") { desk.new() }.keyboardShortcut("n")
                Button("Open…") { desk.opening = true }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close") { desk.close() }.keyboardShortcut("w")
                Button("Save") { desk.save() }.keyboardShortcut("s")
                Button("Export…") { desk.exporting = true }.keyboardShortcut("e")
            }
        }
    }
}

/// The open postcard, the file it is in, and what the app is asking.
@Observable @MainActor
final class PostcardDesk {
    /// The postcard open, or `nil` when none is.
    var postcard: Postcard? = Postcard()
    /// The postcard as it was last saved or opened: what "edited" compares.
    var saved = Postcard()
    /// The file it is in, once saved or opened.
    var fileURL: URL?

    var choosingPicture = false
    var opening = false
    var saving = false
    var exporting = false
    var confirmingClose = false

    /// The chord last pressed and what it does, captioned until the next.
    var caption: String?
    /// What the last save or export did, said at the card's foot.
    var toast: String?

    var isEdited: Bool { postcard.map { $0 != saved } ?? false }

    /// The document's name: its file's, or Untitled.
    var name: String { fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }

    /// The name a first save offers: the picture's.
    var suggestedName: String {
        postcard?.picture.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "Untitled"
    }

    func new() {
        postcard = Postcard()
        saved = Postcard()
        fileURL = nil
        toast = nil
    }

    /// Saves to the postcard's file; a postcard never saved asks where.
    func save() {
        guard let postcard else { return }
        guard let fileURL else {
            saving = true
            return
        }
        try? postcard.data(as: Postcard.type).write(to: fileURL, options: .atomic)
        saved = postcard
    }

    /// Closes the postcard, asking first if it is edited.
    func close() {
        if isEdited { confirmingClose = true } else { closeNow() }
    }

    func closeNow() {
        postcard = nil
        fileURL = nil
        toast = nil
    }

    /// A save panel's file, written: the postcard is in it now.
    func saved(to url: URL) {
        guard let postcard else { return }
        fileURL = url
        saved = postcard
    }

    /// Opens the postcard in the file at `url`.
    func open(_ url: URL) {
        guard let card = Postcard(contentsOf: url) else { return }
        postcard = card
        saved = card
        fileURL = url
        toast = nil
    }
}

/// The app's window: the postcard, the title saying what it is, and the
/// file panels and the question that act on it.
struct PostcardWindow: View {
    @Bindable var desk: PostcardDesk

    enum Field: Hashable {
        case addPicture, message
    }

    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 1) {
            if desk.postcard != nil {
                PostcardCard(desk: desk, focus: $focus)
            } else {
                emptyDesk
            }
            footer
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focus, .addPicture)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 0) {
                    Text(verbatim: desk.postcard == nil ? "Postcards" : desk.name).bold()
                    if desk.isEdited { Text(verbatim: " — Edited").foregroundStyle(.palette.foregroundSecondary) }
                }
            }
            // The chord just pressed, at the toolbar's end: above the sheets,
            // which cover the window's foot.
            ToolbarItem(placement: .primaryAction) {
                if let caption = desk.caption {
                    Text(verbatim: " \(caption) ")
                        .bold()
                        .foregroundStyle(.palette.background)
                        .background(.palette.accent)
                        .transition(.opacity)
                }
            }
        }
        .alert("Save changes to “\(desk.name)”?", isPresented: $desk.confirmingClose) {
            Button("Save") {
                desk.save()
                desk.closeNow()
            }
            Button("Don’t Save", role: .destructive) { desk.closeNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "Your changes will be lost if you don’t save them.")
        }
        .modifier(PostcardPanels(desk: desk, focus: $focus))
        // A new postcard puts the keys on Add Picture…, one with a picture
        // on its message.
        .onChange(of: focusTarget) { _, target in
            if let target { focus = target }
        }
    }

    /// Where the keys go for the postcard open: Add Picture… until it has
    /// a picture, then the message; nowhere with none open.
    private var focusTarget: Field? {
        guard let postcard = desk.postcard else { return nil }
        return postcard.picture == nil ? .addPicture : .message
    }

    /// No postcard open.
    ///
    /// The place the card was, tinted: on the near-black page alone, the
    /// card's picture dimmed under the question was within the WebP
    /// encoder's tolerance of black, and the clip kept a ghost of it.
    private var emptyDesk: some View {
        VStack(spacing: 1) {
            Text(verbatim: "No postcard open").bold()
            Text(verbatim: "⌃N New Postcard   ⌃O Open…").foregroundStyle(.palette.foregroundSecondary)
        }
        .frame(width: 102, height: 24, alignment: .center)
        .background(Color.palette.accent.opacity(0.12))
    }

    /// What the last save or export did.
    private var footer: some View {
        HStack(spacing: 0) {
            if let toast = desk.toast {
                Text(verbatim: "✓ \(toast)").foregroundStyle(.palette.foregroundSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The file panels the window presents: a picture to add, a postcard to
/// open, where to save it, and where to export it, and in what format.
private struct PostcardPanels: ViewModifier {
    @Bindable var desk: PostcardDesk
    let focus: FocusState<PostcardWindow.Field?>.Binding

    func body(content: Content) -> some View {
        content
            // Each panel's own customizations wrap it alone; those after wrap
            // the panels before them too.
            .fileExporter(
                isPresented: $desk.exporting, document: desk.postcard, contentTypes: Postcard.exportTypes,
                defaultFilename: desk.name
            ) { result in
                if case .success(let url) = result { desk.toast = "Exported \(url.lastPathComponent)" }
                focus.wrappedValue = .message
            }
            .fileDialogConfirmationLabel("Export")
            .fileExporter(
                isPresented: $desk.saving, document: desk.postcard, contentTypes: [Postcard.type],
                defaultFilename: desk.suggestedName
            ) { result in
                if case .success(let url) = result { desk.saved(to: url) }
                focus.wrappedValue = .message
            }
            // Saving and exporting keep a view of their own, the list, and
            // the folder they were last in; the open panels keep the columns.
            // Each customization reaches every panel before it in the chain,
            // so each panel states its own where an earlier one differs. One
            // type to save, a dynamic one with no name to show: no pop-up.
            .fileDialogCustomizationID("postcards.save")
            .fileDialogDefaultDirectory(PostcardHome.home)
            .fileDialogContentTypePicker(.automatic)
            .fileImporter(isPresented: $desk.opening, allowedContentTypes: [Postcard.type]) { result in
                if case .success(let url) = result { desk.open(url) }
                focus.wrappedValue = .message
            }
            .fileDialogCustomizationID("postcards.open")
            .fileDialogDefaultDirectory(PostcardHome.postcards)
            .fileDialogContentTypePicker(.automatic)
            .fileImporter(isPresented: $desk.choosingPicture, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result { desk.postcard?.picture = url.path }
                focus.wrappedValue = .message
            }
            .fileDialogCustomizationID("postcards.picture")
            .fileDialogDefaultDirectory(PostcardHome.pictures)
            .fileDialogContentTypePicker(.visible)
            .fileDialogPreview { url, type in PanelPreview.of(url, type: type) }
            .modifier(ColumnViewByDefault())
    }
}

/// The open panels' column view, as a user who keeps it would have left it:
/// the view mode each open panel keeps under its identifier.
private struct ColumnViewByDefault: ViewModifier {
    @AppStorage("TUIFilePanels.postcards.open.viewMode") private var openView = "list"
    @AppStorage("TUIFilePanels.postcards.picture.viewMode") private var pictureView = "list"

    func body(content: Content) -> some View {
        content.onAppear {
            openView = "columns"
            pictureView = "columns"
        }
    }
}

/// The postcard: the picture on the left, or a button to add one; the
/// message on the right, with the stamp and the address, as a card's back.
private struct PostcardCard: View {
    @Bindable var desk: PostcardDesk
    let focus: FocusState<PostcardWindow.Field?>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            picture
                .frame(width: 46, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 1) {
                    // Plain: written on the card, not in a field.
                    TextEditor(text: message)
                        .textEditorStyle(.plain)
                        .focused(focus, equals: .message)
                        .frame(height: 7)
                        // Until the keys come to it: then the caret is
                        // where the placeholder's first letter was.
                        .overlay(alignment: .topLeading) {
                            if message.wrappedValue.isEmpty && focus.wrappedValue != .message {
                                Text(verbatim: "Write a message…").foregroundStyle(.palette.foregroundTertiary)
                            }
                        }
                    stamp
                }
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Sam Rivera")
                    Text(verbatim: "12 Harbour Street")
                    Text(verbatim: "Lisbon 1100-148")
                    Text(verbatim: "Portugal")
                }
                .padding(.leading, 4)
                Spacer(minLength: 0)
            }
        }
        .padding(1)
        .frame(width: 100, height: 22)
        .border()
    }

    private var message: Binding<String> {
        Binding(get: { desk.postcard?.message ?? "" }, set: { desk.postcard?.message = $0 })
    }

    @ViewBuilder private var picture: some View {
        if let path = desk.postcard?.picture {
            Image(.file(path))
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 1) {
                Spacer()
                Text(verbatim: "No picture yet").foregroundStyle(.palette.foregroundSecondary)
                Button("Add Picture…") { desk.choosingPicture = true }
                    .focused(focus, equals: .addPicture)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(.palette.foregroundTertiary)
        }
    }

    /// A stamp: a photograph in a perforated frame.
    private var stamp: some View {
        Image(.file(ClipAssets.photo("bee-drinking")))
            .resizable()
            .scaledToFill()
            .frame(width: 8, height: 4)
            .padding(.horizontal, 1)
            .border(.palette.foregroundTertiary)
    }
}
