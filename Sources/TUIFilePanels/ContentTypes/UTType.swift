//  🖥️ TUI — A Terminal UI framework for Swift
//  UTType.swift
//
//  `UTType` where UniformTypeIdentifiers does not exist: a value naming a
//  content type, known by its identifier, extensions and MIME types from
//  `ContentTypeTable`, so `allowedContentTypes: [.pdf]` compiles and means the
//  same on Linux as it does on macOS.
//
//  Created by Wade Tregaskis
//  License: MIT

#if !canImport(UniformTypeIdentifiers)

    // MARK: - The type

    /// A structure that represents a type of data to load, send, or receive —
    /// UniformTypeIdentifiers' `UTType`, declared by TUI where that framework
    /// does not exist.
    ///
    /// On Apple platforms TUI's file panels take UniformTypeIdentifiers' own
    /// `UTType`, which this module does not re-export, as SwiftUI does not: a
    /// file that names `UTType` imports UniformTypeIdentifiers itself. That
    /// framework is Apple's alone, so elsewhere this module declares this type
    /// in its place, with the same spelling, and the same members a file panel's
    /// caller uses: the identifier, the preferred extension and MIME type, the
    /// types it conforms to, and the static members that name the common types.
    /// So `fileImporter(isPresented:allowedContentTypes:onCompletion:)` with
    /// `[.pdf, .plainText]` compiles on Linux unchanged; a file that imports
    /// UniformTypeIdentifiers wraps that import in
    /// `#if canImport(UniformTypeIdentifiers)`.
    ///
    /// What it knows comes from a table read off UniformTypeIdentifiers on
    /// macOS 15.8 (`ContentTypeTable`): about ninety types, every one a static
    /// member names, with their extensions, MIME types and conformances. A file
    /// is typed by its extension, as `UTType(filenameExtension:)` types it;
    /// an extension the table does not know gives a dynamic type conforming to
    /// ``data``, as Apple's does. There is no system type database to declare
    /// an app's own types in, so ``init(exportedAs:conformingTo:)`` and
    /// ``init(importedAs:conformingTo:)`` make a type of that identifier that
    /// conforms to the parent given and has no extension; to type an app's
    /// files by their extension, use ``init(filenameExtension:conformingTo:)``,
    /// which works on every platform.
    public struct UTType: Sendable {
        /// The type's identifier: `public.png`, or a dynamic type's.
        public let identifier: String

        /// What a type outside the table knows of itself: a dynamic type's tag
        /// and parent, or an app-declared type's parent. `nil` for a type the
        /// table declares, whose record says all of it.
        private let undeclared: Undeclared?

        /// A type the table does not declare.
        private struct Undeclared: Sendable {
            /// The extension that named it, when one did.
            var filenameExtension: String?
            /// The MIME type that named it, when one did.
            var mimeType: String?
            /// The type it was made to conform to, when one was given.
            var parent: [UTType]
            /// Whether it was made from a tag rather than declared by an app.
            var isDynamic: Bool
        }

        /// A type the table declares. The static members are made with it.
        init(declared identifier: String) {
            self.identifier = identifier
            self.undeclared = nil
        }

        private init(identifier: String, undeclared: Undeclared) {
            self.identifier = identifier
            self.undeclared = undeclared
        }

        /// The record of the type, when the table declares it.
        private var record: ContentTypeRecord? {
            undeclared == nil ? ContentTypeTable.record(identifier) : nil
        }
    }

    // MARK: - Making a type

    extension UTType {
        /// Creates a type from its identifier, or `nil` when no type of that
        /// identifier is declared — in this table, which stands in for the
        /// system's type database.
        ///
        /// - Parameter identifier: The identifier, `public.png`.
        public init?(_ identifier: String) {
            guard ContentTypeTable.record(identifier) != nil else { return nil }
            self.init(declared: identifier)
        }

        /// Creates the type a filename extension names, conforming to
        /// `supertype`.
        ///
        /// The declared type that extension names when it conforms to
        /// `supertype`, as UniformTypeIdentifiers answers; otherwise a dynamic
        /// type that conforms to `supertype` and has the extension as its
        /// preferred one. The extension is matched without regard to case.
        ///
        /// - Parameters:
        ///   - filenameExtension: The extension, without its leading dot.
        ///   - supertype: The type the result must conform to; ``data`` by
        ///     default.
        /// - Returns: `nil` for an empty extension.
        public init?(filenameExtension: String, conformingTo supertype: UTType = .data) {
            guard !filenameExtension.isEmpty else { return nil }
            if let record = ContentTypeTable.record(forExtension: filenameExtension),
                UTType(declared: record.identifier).conforms(to: supertype)
            {
                self.init(declared: record.identifier)
                return
            }
            let name = filenameExtension.lowercased()
            self.init(
                identifier: Self.dynamicIdentifier(tag: "ext=" + name, parent: supertype),
                undeclared: Undeclared(filenameExtension: name, mimeType: nil, parent: [supertype], isDynamic: true))
        }

        /// Creates the type a MIME type names, conforming to `supertype`.
        ///
        /// The declared type that MIME type names when it conforms to
        /// `supertype`; otherwise a dynamic type that conforms to `supertype`
        /// and has the MIME type as its preferred one. Matched without regard
        /// to case.
        ///
        /// - Parameters:
        ///   - mimeType: The MIME type, `image/png`.
        ///   - supertype: The type the result must conform to; ``data`` by
        ///     default.
        /// - Returns: `nil` for an empty MIME type.
        public init?(mimeType: String, conformingTo supertype: UTType = .data) {
            guard !mimeType.isEmpty else { return nil }
            if let record = ContentTypeTable.record(forMIMEType: mimeType),
                UTType(declared: record.identifier).conforms(to: supertype)
            {
                self.init(declared: record.identifier)
                return
            }
            let name = mimeType.lowercased()
            self.init(
                identifier: Self.dynamicIdentifier(tag: "mime=" + name, parent: supertype),
                undeclared: Undeclared(filenameExtension: nil, mimeType: name, parent: [supertype], isDynamic: true))
        }

        /// Creates a type the app declares and owns.
        ///
        /// The table's type when it declares `identifier`; otherwise one of
        /// that identifier that conforms to `parentType`, with no extension or
        /// MIME type, since there is no system type database to declare those
        /// in. To type an app's own files by their extension, use
        /// ``init(filenameExtension:conformingTo:)``.
        ///
        /// - Parameters:
        ///   - identifier: The type's identifier, `com.example.note`.
        ///   - parentType: The type it conforms to, if any.
        public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) {
            if ContentTypeTable.record(identifier) != nil {
                self.init(declared: identifier)
                return
            }
            self.init(
                identifier: identifier,
                undeclared: Undeclared(
                    filenameExtension: nil, mimeType: nil, parent: parentType.map { [$0] } ?? [], isDynamic: false))
        }

        /// Creates a type another party declares, which the app uses.
        ///
        /// The same as ``init(exportedAs:conformingTo:)`` here: with no system
        /// type database, there is no difference between declaring a type and
        /// importing one.
        ///
        /// - Parameters:
        ///   - identifier: The type's identifier.
        ///   - parentType: The type it conforms to, if any.
        public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) {
            self.init(exportedAs: identifier, conformingTo: parentType)
        }

        /// A dynamic type's identifier: unique to its tag and its parent, as
        /// UniformTypeIdentifiers' `dyn.` identifiers are, though not spelt as
        /// theirs (which encode both in a private scheme).
        private static func dynamicIdentifier(tag: String, parent: UTType) -> String {
            parent.identifier == "public.data" ? "dyn.\(tag)" : "dyn.\(tag);\(parent.identifier)"
        }
    }

    // MARK: - What a type knows

    extension UTType {
        /// The extension a file of this type is preferably given, without its
        /// dot, or `nil` when the type has none.
        public var preferredFilenameExtension: String? {
            record?.extensions.first ?? undeclared?.filenameExtension
        }

        /// The MIME type this type preferably goes by, or `nil` when it has none.
        public var preferredMIMEType: String? {
            record?.mimeTypes.first ?? undeclared?.mimeType
        }

        /// The type's description — in English, as macOS 15.8 describes it
        /// (there are no system localizations to read here) — or `nil` for a
        /// type the table does not declare.
        public var localizedDescription: String? { record?.description }

        /// Whether the type was made from a tag the table does not know: an
        /// extension or a MIME type.
        public var isDynamic: Bool { undeclared?.isDynamic ?? false }

        /// Whether the type is declared: in the table, or by the app with
        /// ``init(exportedAs:conformingTo:)`` or ``init(importedAs:conformingTo:)``.
        public var isDeclared: Bool { !isDynamic }

        /// Whether the type is one of the public types, whose identifiers begin
        /// `public.`.
        public var isPublic: Bool { record != nil && identifier.hasPrefix("public.") }

        /// The types this type conforms to, directly or through others, itself
        /// excluded.
        public var supertypes: Set<UTType> {
            guard let undeclared else {
                return Set(ContentTypeTable.ancestors(of: identifier).map(Self.init(declared:)))
            }
            var found: Set<UTType> = []
            for parent in undeclared.parent {
                found.insert(parent)
                found.formUnion(parent.supertypes)
            }
            return found
        }

        /// Whether this type is `type`, or conforms to it.
        ///
        /// - Parameter type: The type to test against.
        public func conforms(to type: UTType) -> Bool {
            self == type || supertypes.contains(type)
        }

        /// Whether `type` conforms to this type, and is not this type.
        ///
        /// - Parameter type: The type to test.
        public func isSupertype(of type: UTType) -> Bool {
            self != type && type.conforms(to: self)
        }

        /// Whether this type conforms to `type`, and is not that type.
        ///
        /// - Parameter type: The type to test against.
        public func isSubtype(of type: UTType) -> Bool {
            self != type && conforms(to: type)
        }
    }

    // MARK: - Conformances

    extension UTType: Hashable {
        /// Two types are equal when their identifiers are, as UniformTypeIdentifiers'
        /// are.
        public static func == (lhs: UTType, rhs: UTType) -> Bool {
            lhs.identifier == rhs.identifier
        }

        /// Hashes the identifier, the one thing equality compares.
        public func hash(into hasher: inout Hasher) {
            hasher.combine(identifier)
        }
    }

    extension UTType: CustomStringConvertible, CustomDebugStringConvertible {
        /// The identifier, as UniformTypeIdentifiers' `description` is.
        public var description: String { identifier }

        /// The identifier, and whether the type is dynamic or declared.
        public var debugDescription: String {
            "\(identifier) (\(isDynamic ? "dynamic" : "not dynamic"), \(isDeclared ? "declared" : "undeclared"))"
        }
    }

    extension UTType: Codable {
        /// Writes the type as its identifier.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(identifier)
        }

        /// Reads a type written as its identifier: the table's type of that
        /// identifier, or else a type imported under it.
        public init(from decoder: any Decoder) throws {
            let identifier = try decoder.singleValueContainer().decode(String.self)
            self = UTType(identifier) ?? UTType(importedAs: identifier)
        }
    }

    // MARK: - The common types

    /// The types UniformTypeIdentifiers names with static members, each the
    /// table's record of the same identifier.
    extension UTType {
        /// `public.item`: item.
        public static let item = UTType(declared: "public.item")

        /// `public.content`: content.
        public static let content = UTType(declared: "public.content")

        /// `public.composite-content`: content.
        public static let compositeContent = UTType(declared: "public.composite-content")

        /// `public.data`: data.
        public static let data = UTType(declared: "public.data")

        /// `public.directory`: directory.
        public static let directory = UTType(declared: "public.directory")

        /// `public.folder`: folder.
        public static let folder = UTType(declared: "public.folder")

        /// `public.volume`: volume.
        public static let volume = UTType(declared: "public.volume")

        /// `com.apple.package`: Package.
        public static let package = UTType(declared: "com.apple.package")

        /// `com.apple.bundle`: bundle.
        public static let bundle = UTType(declared: "com.apple.bundle")

        /// `com.apple.resolvable`: resolvable.
        public static let resolvable = UTType(declared: "com.apple.resolvable")

        /// `public.symlink`: symbolic link.
        public static let symbolicLink = UTType(declared: "public.symlink")

        /// `public.executable`: executable.
        public static let executable = UTType(declared: "public.executable")

        /// `public.unix-executable`: Unix executable.
        public static let unixExecutable = UTType(declared: "public.unix-executable")

        /// `com.apple.application`: application.
        public static let application = UTType(declared: "com.apple.application")

        /// `com.apple.application-bundle`: application.
        public static let applicationBundle = UTType(declared: "com.apple.application-bundle")

        /// `public.url`: URL.
        public static let url = UTType(declared: "public.url")

        /// `public.file-url`: file URL.
        public static let fileURL = UTType(declared: "public.file-url")

        /// `public.text`: text.
        public static let text = UTType(declared: "public.text")

        /// `public.plain-text`: text.
        public static let plainText = UTType(declared: "public.plain-text")

        /// `public.utf8-plain-text`: text.
        public static let utf8PlainText = UTType(declared: "public.utf8-plain-text")

        /// `public.delimited-values-text`: delimited text values.
        public static let delimitedText = UTType(declared: "public.delimited-values-text")

        /// `public.comma-separated-values-text`: comma-separated values.
        public static let commaSeparatedText = UTType(declared: "public.comma-separated-values-text")

        /// `public.tab-separated-values-text`: tab-separated values.
        public static let tabSeparatedText = UTType(declared: "public.tab-separated-values-text")

        /// `public.utf8-tab-separated-values-text`: tab-separated values.
        public static let utf8TabSeparatedText = UTType(declared: "public.utf8-tab-separated-values-text")

        /// `public.rtf`: rich text (RTF).
        public static let rtf = UTType(declared: "public.rtf")

        /// `public.html`: HTML text.
        public static let html = UTType(declared: "public.html")

        /// `public.xml`: XML text.
        public static let xml = UTType(declared: "public.xml")

        /// `public.yaml`: YAML.
        public static let yaml = UTType(declared: "public.yaml")

        /// `public.json`: JSON.
        public static let json = UTType(declared: "public.json")

        /// `com.apple.property-list`: property list.
        public static let propertyList = UTType(declared: "com.apple.property-list")

        /// `com.apple.xml-property-list`: XML property list.
        public static let xmlPropertyList = UTType(declared: "com.apple.xml-property-list")

        /// `com.apple.binary-property-list`: binary property list.
        public static let binaryPropertyList = UTType(declared: "com.apple.binary-property-list")

        /// `public.log`: Log file.
        public static let log = UTType(declared: "public.log")

        /// `public.source-code`: source code.
        public static let sourceCode = UTType(declared: "public.source-code")

        /// `public.swift-source`: Swift Source Code.
        public static let swiftSource = UTType(declared: "public.swift-source")

        /// `public.c-source`: C source code.
        public static let cSource = UTType(declared: "public.c-source")

        /// `public.c-header`: C header code.
        public static let cHeader = UTType(declared: "public.c-header")

        /// `public.c-plus-plus-source`: C++ source code.
        public static let cPlusPlusSource = UTType(declared: "public.c-plus-plus-source")

        /// `public.c-plus-plus-header`: C++ header code.
        public static let cPlusPlusHeader = UTType(declared: "public.c-plus-plus-header")

        /// `public.objective-c-source`: Objective-C source code.
        public static let objectiveCSource = UTType(declared: "public.objective-c-source")

        /// `public.objective-c-plus-plus-source`: Objective-C++ source code.
        public static let objectiveCPlusPlusSource = UTType(declared: "public.objective-c-plus-plus-source")

        /// `public.assembly-source`: assembly source code.
        public static let assemblyLanguageSource = UTType(declared: "public.assembly-source")

        /// `public.script`: script.
        public static let script = UTType(declared: "public.script")

        /// `public.shell-script`: shell script.
        public static let shellScript = UTType(declared: "public.shell-script")

        /// `public.python-script`: Python script.
        public static let pythonScript = UTType(declared: "public.python-script")

        /// `public.ruby-script`: Ruby script.
        public static let rubyScript = UTType(declared: "public.ruby-script")

        /// `public.perl-script`: Perl script.
        public static let perlScript = UTType(declared: "public.perl-script")

        /// `com.netscape.javascript-source`: JavaScript.
        public static let javaScript = UTType(declared: "com.netscape.javascript-source")

        /// `com.adobe.pdf`: PDF document.
        public static let pdf = UTType(declared: "com.adobe.pdf")

        /// `org.idpf.epub-container`: EPUB publication.
        public static let epub = UTType(declared: "org.idpf.epub-container")

        /// `public.image`: image.
        public static let image = UTType(declared: "public.image")

        /// `public.png`: PNG image.
        public static let png = UTType(declared: "public.png")

        /// `public.jpeg`: JPEG image.
        public static let jpeg = UTType(declared: "public.jpeg")

        /// `com.compuserve.gif`: GIF image.
        public static let gif = UTType(declared: "com.compuserve.gif")

        /// `public.tiff`: TIFF image.
        public static let tiff = UTType(declared: "public.tiff")

        /// `com.microsoft.bmp`: Windows BMP image.
        public static let bmp = UTType(declared: "com.microsoft.bmp")

        /// `public.svg-image`: SVG image.
        public static let svg = UTType(declared: "public.svg-image")

        /// `public.heic`: HEIF Image.
        public static let heic = UTType(declared: "public.heic")

        /// `org.webmproject.webp`: WebP Image.
        public static let webP = UTType(declared: "org.webmproject.webp")

        /// `com.microsoft.ico`: Windows icon image.
        public static let ico = UTType(declared: "com.microsoft.ico")

        /// `public.camera-raw-image`: camera raw image.
        public static let rawImage = UTType(declared: "public.camera-raw-image")

        /// `public.audiovisual-content`: Audiovisual Content.
        public static let audiovisualContent = UTType(declared: "public.audiovisual-content")

        /// `public.movie`: movie.
        public static let movie = UTType(declared: "public.movie")

        /// `public.video`: video.
        public static let video = UTType(declared: "public.video")

        /// `public.audio`: Audio.
        public static let audio = UTType(declared: "public.audio")

        /// `public.mpeg-4`: MPEG-4 movie.
        public static let mpeg4Movie = UTType(declared: "public.mpeg-4")

        /// `com.apple.quicktime-movie`: QuickTime movie.
        public static let quickTimeMovie = UTType(declared: "com.apple.quicktime-movie")

        /// `public.mp3`: MP3 audio.
        public static let mp3 = UTType(declared: "public.mp3")

        /// `com.microsoft.waveform-audio`: Waveform audio.
        public static let wav = UTType(declared: "com.microsoft.waveform-audio")

        /// `public.mpeg-4-audio`: MPEG-4 audio.
        public static let mpeg4Audio = UTType(declared: "public.mpeg-4-audio")

        /// `public.aiff-audio`: AIFF audio.
        public static let aiff = UTType(declared: "public.aiff-audio")

        /// `public.archive`: file archive.
        public static let archive = UTType(declared: "public.archive")

        /// `public.zip-archive`: Zip archive.
        public static let zip = UTType(declared: "public.zip-archive")

        /// `org.gnu.gnu-zip-archive`: GZip archive.
        public static let gzip = UTType(declared: "org.gnu.gnu-zip-archive")

        /// `public.bzip2-archive`: Bzip2 archive.
        public static let bz2 = UTType(declared: "public.bzip2-archive")

        /// `public.disk-image`: disk image.
        public static let diskImage = UTType(declared: "public.disk-image")

        /// `public.font`: font.
        public static let font = UTType(declared: "public.font")

        /// `public.database`: database.
        public static let database = UTType(declared: "public.database")

        /// `public.spreadsheet`: Spreadsheet.
        public static let spreadsheet = UTType(declared: "public.spreadsheet")

        /// `public.presentation`: presentation.
        public static let presentation = UTType(declared: "public.presentation")

        /// `public.message`: message.
        public static let message = UTType(declared: "public.message")

        /// `public.email-message`: email message.
        public static let emailMessage = UTType(declared: "public.email-message")

        /// `public.contact`: contact information.
        public static let contact = UTType(declared: "public.contact")

        /// `public.vcard`: electronic business card.
        public static let vCard = UTType(declared: "public.vcard")

        /// `public.calendar-event`: calendar event.
        public static let calendarEvent = UTType(declared: "public.calendar-event")
    }

#endif
