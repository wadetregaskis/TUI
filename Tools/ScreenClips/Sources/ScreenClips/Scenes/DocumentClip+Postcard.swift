//  🖥️ TUI — A Terminal UI framework for Swift
//  DocumentClip+Postcard.swift
//
//  The `document` clip's document and its files: a postcard (a picture and a
//  message) as a `FileDocument`, the home folder the clip's file panels
//  browse, made afresh for every run, and the previews the panels draw.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI
import UniformTypeIdentifiers

/// A postcard: the picture on its front and the message on its back.
///
/// Saved as a `.postcard` file, its two fields as JSON; exported as plain
/// text, Markdown or HTML.
struct Postcard: FileDocument, Codable, Equatable {
    /// A `.postcard` file. Dynamic, since a clip has no Info.plist to declare
    /// a type in: the type the system gives any file of the extension, so the
    /// open panel's filter and the file system agree on it.
    static let type = UTType(filenameExtension: "postcard") ?? .json

    /// Markdown, which UniformTypeIdentifiers names no constant for.
    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    /// The formats Export… offers, in its Format pop-up's order.
    static let exportTypes: [UTType] = [.plainText, markdown, .html]

    static var readableContentTypes: [UTType] { [type] }
    static var writableContentTypes: [UTType] { [type] + exportTypes }

    /// The picture's path, or `nil` for a postcard with none yet.
    var picture: String?
    var message = ""

    init(picture: String? = nil, message: String = "") {
        self.picture = picture
        self.message = message
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    /// The postcard in a file at `url`, or `nil` where there is none.
    init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url), let card = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = card
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try data(as: configuration.contentType))
    }

    /// The postcard as a file of `type`.
    func data(as type: UTType) throws -> Data {
        let pictureURL = picture.map { URL(fileURLWithPath: $0).absoluteString } ?? ""
        switch type {
        case Self.type:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(self)
        case Self.markdown:
            return Data("![](\(pictureURL))\n\n\(message)\n".utf8)
        case .html:
            return Data("<figure><img src=\"\(pictureURL)\"><figcaption>\(message)</figcaption></figure>\n".utf8)
        default:
            return Data((message + "\n").utf8)
        }
    }
}

/// The clip's home folder: what its file panels browse as `~`, made afresh
/// for every run beside the staged player — never the user's own.
///
/// The app runs with `CFFIXED_USER_HOME` naming it (``Clip/environment``),
/// so Foundation's home folder, which the panels start from and abbreviate
/// as `~`, is this one.
enum PostcardHome {
    /// Where it is made: beside the stage's `bin`, outside `~/Documents`,
    /// which Ghostty may not open files in.
    static let root = ClipAssets.directory.deletingLastPathComponent()
        .appendingPathComponent("postcard-home", isDirectory: true)

    /// The home folder as the app's Foundation sees it: `root`, spelled as
    /// it resolves (`/tmp` for `/private/tmp`), which the panels' paths use.
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var pictures: URL { home.appendingPathComponent("Pictures", isDirectory: true) }
    static var postcards: URL { home.appendingPathComponent("Postcards", isDirectory: true) }

    /// The photographs in Pictures, by the name each is saved under.
    private static let photos = [
        ("bald-eagle", "Bald eagle"), ("burrowing-owl", "Burrowing owl"), ("cedar-waxwings", "Cedar waxwings"),
        ("fawn", "Fawn"), ("galago", "Galago"), ("lioness", "Lioness"),
        ("pigeon-point-lighthouse", "Pigeon Point"), ("snail", "Snail"), ("spurred-tortoise", "Spurred tortoise"),
    ]

    /// Makes the home folder again from nothing: the usual folders, the
    /// photographs in Pictures with a note among them that is no picture,
    /// and two postcards already sent. Refuses, and ends the app, where the
    /// home folder Foundation sees is not `root`: run without
    /// `CFFIXED_USER_HOME`, this would write into the user's own.
    static func make() {
        let files = FileManager.default
        guard home.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path else {
            FileHandle.standardError.write(Data("document: the home folder is not \(root.path); not touching it\n".utf8))
            exit(1)
        }
        try? files.removeItem(at: home)
        for folder in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Postcards"] {
            try? files.createDirectory(
                at: home.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        for (file, name) in photos {
            try? files.copyItem(
                at: URL(fileURLWithPath: ClipAssets.photo(file)),
                to: pictures.appendingPathComponent("\(name).webp"))
        }
        try? Data("Ferry at 9:40. Owls at the burrows by the lighthouse road.\n".utf8)
            .write(to: pictures.appendingPathComponent("Trip notes.txt"))
        let sent = [
            ("Galago", "Galago", "Up all night again. The galagos send their love."),
            ("Pigeon Point", "Pigeon Point", "Fog all morning, then this. The light still turns!"),
        ]
        for (file, picture, message) in sent {
            let card = Postcard(picture: pictures.appendingPathComponent("\(picture).webp").path, message: message)
            try? card.data(as: Postcard.type).write(to: postcards.appendingPathComponent("\(file).postcard"))
        }
    }
}

/// What the column view of the clip's panels previews: a picture, drawn; a
/// postcard, its picture over its message, as the card itself shows them.
struct PanelPreview: View {
    let picture: String?
    let message: String?

    /// The preview of the item at `url`, of `type`: a picture's or a
    /// postcard's; `nil`, TUI's own, for anything else.
    static func of(_ url: URL, type: UTType) -> Self? {
        if type.conforms(to: .image) { return Self(picture: url.path, message: nil) }
        if type == Postcard.type, let card = Postcard(contentsOf: url) {
            return Self(picture: card.picture, message: card.message)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let picture {
                Image(.file(picture))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: message == nil ? .infinity : .fixed(9))
            }
            if let message {
                Text(verbatim: message)
                    .italic()
                    .foregroundStyle(.palette.foregroundSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
