//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentTypeTable.swift
//
//  The content types a file panel knows by name, extension and MIME type
//  where UniformTypeIdentifiers does not exist: the declarations behind
//  TUIkit's own `UTType` on Linux (UTType.swift), and the extension-based
//  fallback a panel types a file by there.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A declared type

/// One content type, as UniformTypeIdentifiers declares it: its identifier, the
/// filename extensions and MIME types that name it (the preferred one first),
/// the types it conforms to directly, and its English description.
///
/// Compiled everywhere, though only Linux's `UTType` reads it, so that the
/// tests on macOS can hold every record to what UniformTypeIdentifiers itself
/// says about the same identifier (`ContentTypeTableTests`).
struct ContentTypeRecord: Sendable {
    /// The type's identifier, `public.png`.
    let identifier: String

    /// The filename extensions that name it, lowercased, the preferred one first.
    let extensions: [String]

    /// The MIME types that name it, the preferred one first.
    let mimeTypes: [String]

    /// The identifiers of the types it conforms to directly.
    let parents: [String]

    /// The type's description, in English: macOS 15.8's `localizedDescription`.
    let description: String

    init(
        _ identifier: String, extensions: [String] = [], mimeTypes: [String] = [], parents: [String] = [],
        description: String
    ) {
        self.identifier = identifier
        self.extensions = extensions
        self.mimeTypes = mimeTypes
        self.parents = parents
        self.description = description
    }
}

// MARK: - The table

/// The declared types, and the three indexes a lookup goes through.
///
/// The records were read off UniformTypeIdentifiers on macOS 15.8 (the session
/// notes' O10/probe/uttgen.swift): every type a `UTType` static member names,
/// the types those conform to, and a few a file is commonly named for that
/// have no static member (Markdown, tar). Each record lists only the parents
/// this table has, and only the nearest of them, so conformance is the
/// transitive walk over `parents`. Where two records share an extension, the
/// first one listed is the one the extension names, as `UTType(filenameExtension:)`
/// answers: `text` is plain text before it is Markdown, `plist` a property list
/// before it is an XML one, and `mp4` a movie before it is audio.
enum ContentTypeTable {
    /// Every declared type.
    static let records: [ContentTypeRecord] = [
        ContentTypeRecord("public.item", description: "item"),
        ContentTypeRecord("public.content", description: "content"),
        ContentTypeRecord("public.composite-content", parents: ["public.content"], description: "content"),
        ContentTypeRecord("public.data", parents: ["public.item"], description: "data"),
        ContentTypeRecord("public.directory", parents: ["public.item"], description: "directory"),
        ContentTypeRecord("public.folder", parents: ["public.directory"], description: "folder"),
        ContentTypeRecord("public.volume", parents: ["public.folder"], description: "volume"),
        ContentTypeRecord("com.apple.package", parents: ["public.directory"], description: "Package"),
        ContentTypeRecord("com.apple.bundle", parents: ["public.directory"], description: "bundle"),
        ContentTypeRecord("com.apple.resolvable", description: "resolvable"),
        ContentTypeRecord("public.symlink", parents: ["com.apple.resolvable", "public.item"],
            description: "symbolic link"),
        ContentTypeRecord("public.executable", description: "executable"),
        ContentTypeRecord("public.unix-executable", parents: ["public.data", "public.executable"],
            description: "Unix executable"),
        ContentTypeRecord("com.apple.application", parents: ["public.executable"], description: "application"),
        // Before the bundle: `UTType(filenameExtension: "app")` names the file
        // form (measured), though the bundle lists the extension too.
        ContentTypeRecord("com.apple.application-file", extensions: ["app"],
            parents: ["com.apple.application", "public.data"], description: "application"),
        ContentTypeRecord("com.apple.application-bundle", extensions: ["app"],
            parents: ["com.apple.application", "com.apple.bundle", "com.apple.package"], description: "application"),
        ContentTypeRecord("public.url", parents: ["public.data"], description: "URL"),
        ContentTypeRecord("public.file-url", parents: ["public.url"], description: "file URL"),
        ContentTypeRecord("public.text", parents: ["public.content", "public.data"], description: "text"),
        ContentTypeRecord("public.plain-text", extensions: ["txt", "text"], mimeTypes: ["text/plain"],
            parents: ["public.text"], description: "text"),
        ContentTypeRecord("public.utf8-plain-text",
            mimeTypes: ["text/plain;charset=utf-8", "text/plain;charset=\"utf-8\""], parents: ["public.plain-text"],
            description: "text"),
        ContentTypeRecord("public.delimited-values-text", parents: ["public.text"],
            description: "delimited text values"),
        ContentTypeRecord("public.comma-separated-values-text", extensions: ["csv"],
            mimeTypes: ["text/csv", "text/comma-separated-values"],
            parents: ["public.delimited-values-text", "public.plain-text"], description: "comma-separated values"),
        ContentTypeRecord("public.tab-separated-values-text", extensions: ["tsv"],
            mimeTypes: ["text/tab-separated-values"], parents: ["public.delimited-values-text", "public.plain-text"],
            description: "tab-separated values"),
        ContentTypeRecord("public.utf8-tab-separated-values-text",
            parents: ["public.tab-separated-values-text", "public.utf8-plain-text"],
            description: "tab-separated values"),
        ContentTypeRecord("public.rtf", extensions: ["rtf"], mimeTypes: ["text/rtf"], parents: ["public.text"],
            description: "rich text (RTF)"),
        ContentTypeRecord("public.html", extensions: ["html", "htm", "shtml", "shtm"], mimeTypes: ["text/html"],
            parents: ["public.text"], description: "HTML text"),
        ContentTypeRecord("public.xml", extensions: ["xml"], mimeTypes: ["application/xml", "text/xml"],
            parents: ["public.text"], description: "XML text"),
        ContentTypeRecord("public.yaml", extensions: ["yml", "yaml"], mimeTypes: ["application/x-yaml"],
            parents: ["public.text"], description: "YAML"),
        ContentTypeRecord("public.json", extensions: ["json"], mimeTypes: ["application/json"],
            parents: ["public.text"], description: "JSON"),
        ContentTypeRecord("net.daringfireball.markdown", extensions: ["md", "mdown", "markdown", "text"],
            mimeTypes: ["text/markdown", "text/x-markdown", "text/x-web-markdown"], parents: ["public.plain-text"],
            description: "Markdown Text"),
        ContentTypeRecord("com.apple.property-list", extensions: ["plist"], parents: ["public.data"],
            description: "property list"),
        ContentTypeRecord("com.apple.xml-property-list", extensions: ["plist"],
            parents: ["com.apple.property-list", "public.xml"], description: "XML property list"),
        ContentTypeRecord("com.apple.binary-property-list", extensions: ["plist"],
            parents: ["com.apple.property-list"], description: "binary property list"),
        ContentTypeRecord("public.log", parents: ["public.item"], description: "Log file"),
        ContentTypeRecord("public.source-code", parents: ["public.plain-text"], description: "source code"),
        ContentTypeRecord("public.swift-source", extensions: ["swift"], parents: ["public.source-code"],
            description: "Swift Source Code"),
        ContentTypeRecord("public.c-source", extensions: ["c"], parents: ["public.source-code"],
            description: "C source code"),
        ContentTypeRecord("public.c-header", extensions: ["h"], parents: ["public.source-code"],
            description: "C header code"),
        ContentTypeRecord("public.c-plus-plus-source", extensions: ["cp", "cpp", "c++", "cc", "cxx"],
            parents: ["public.source-code"], description: "C++ source code"),
        ContentTypeRecord("public.c-plus-plus-header", extensions: ["hh", "hp", "hpp", "hxx", "h++", "ipp"],
            parents: ["public.source-code"], description: "C++ header code"),
        ContentTypeRecord("public.objective-c-source", extensions: ["m"], parents: ["public.source-code"],
            description: "Objective-C source code"),
        ContentTypeRecord("public.objective-c-plus-plus-source", extensions: ["mm"], parents: ["public.source-code"],
            description: "Objective-C++ source code"),
        ContentTypeRecord("public.assembly-source", extensions: ["s"], parents: ["public.source-code"],
            description: "assembly source code"),
        ContentTypeRecord("public.script", parents: ["public.source-code"], description: "script"),
        ContentTypeRecord("public.shell-script", extensions: ["sh"], parents: ["public.script"],
            description: "shell script"),
        ContentTypeRecord("public.python-script", extensions: ["py"], mimeTypes: ["text/x-python-script"],
            parents: ["public.shell-script"], description: "Python script"),
        ContentTypeRecord("public.ruby-script", extensions: ["rb", "rbw"], mimeTypes: ["text/x-ruby-script"],
            parents: ["public.shell-script"], description: "Ruby script"),
        ContentTypeRecord("public.perl-script", extensions: ["pl", "pm"], mimeTypes: ["text/x-perl-script"],
            parents: ["public.shell-script"], description: "Perl script"),
        ContentTypeRecord("com.netscape.javascript-source", extensions: ["js", "jscript", "javascript", "mjs"],
            mimeTypes: ["text/javascript"], parents: ["public.executable", "public.script"],
            description: "JavaScript"),
        ContentTypeRecord("com.adobe.pdf", extensions: ["pdf"], mimeTypes: ["application/pdf"],
            parents: ["public.composite-content", "public.data"], description: "PDF document"),
        ContentTypeRecord("org.idpf.epub-container", extensions: ["epub"], mimeTypes: ["application/epub+zip"],
            parents: ["public.composite-content", "public.data"], description: "EPUB publication"),
        ContentTypeRecord("public.image", parents: ["public.content", "public.data"], description: "image"),
        ContentTypeRecord("public.png", extensions: ["png"], mimeTypes: ["image/png"], parents: ["public.image"],
            description: "PNG image"),
        ContentTypeRecord("public.jpeg", extensions: ["jpeg", "jpg", "jpe"], mimeTypes: ["image/jpeg", "image/jpg"],
            parents: ["public.image"], description: "JPEG image"),
        ContentTypeRecord("com.compuserve.gif", extensions: ["gif"], mimeTypes: ["image/gif"],
            parents: ["public.image"], description: "GIF image"),
        ContentTypeRecord("public.tiff", extensions: ["tiff", "tif"], mimeTypes: ["image/tiff"],
            parents: ["public.image"], description: "TIFF image"),
        ContentTypeRecord("com.microsoft.bmp", extensions: ["bmp", "dib"], mimeTypes: ["image/bmp"],
            parents: ["public.image"], description: "Windows BMP image"),
        ContentTypeRecord("public.svg-image", extensions: ["svg", "svgz"], mimeTypes: ["image/svg+xml"],
            parents: ["public.image", "public.xml"], description: "SVG image"),
        ContentTypeRecord("public.heif-standard", parents: ["public.image"], description: "HEIF Image"),
        ContentTypeRecord("public.heic", extensions: ["heic"], mimeTypes: ["image/heic"],
            parents: ["public.heif-standard"], description: "HEIF Image"),
        ContentTypeRecord("org.webmproject.webp", extensions: ["webp"], mimeTypes: ["image/webp"],
            parents: ["public.image"], description: "WebP Image"),
        ContentTypeRecord("com.microsoft.ico", extensions: ["ico"], mimeTypes: ["image/vnd.microsoft.icon"],
            parents: ["public.image"], description: "Windows icon image"),
        ContentTypeRecord("public.camera-raw-image", parents: ["public.image"], description: "camera raw image"),
        ContentTypeRecord("public.audiovisual-content", parents: ["public.content", "public.data"],
            description: "Audiovisual Content"),
        ContentTypeRecord("public.movie", parents: ["public.audiovisual-content"], description: "movie"),
        ContentTypeRecord("public.video", parents: ["public.movie"], description: "video"),
        ContentTypeRecord("public.audio", parents: ["public.audiovisual-content"], description: "Audio"),
        ContentTypeRecord("public.mpeg-4", extensions: ["mp4", "mpg4"], mimeTypes: ["video/mp4", "video/mp4v-es"],
            parents: ["public.movie"], description: "MPEG-4 movie"),
        ContentTypeRecord("com.apple.quicktime-movie", extensions: ["mov", "qt"], mimeTypes: ["video/quicktime"],
            parents: ["public.movie"], description: "QuickTime movie"),
        ContentTypeRecord("public.mp3", extensions: ["mp3", "mpga"],
            mimeTypes: [
                "audio/mpeg", "audio/mpeg3", "audio/mpg", "audio/mp3", "audio/x-mpeg", "audio/x-mpeg3", "audio/x-mpg",
                "audio/x-mp3",
            ], parents: ["public.audio"], description: "MP3 audio"),
        ContentTypeRecord("com.microsoft.waveform-audio", extensions: ["wav", "wave", "bwf"],
            mimeTypes: ["audio/vnd.wave", "audio/wav", "audio/wave", "audio/x-wav"], parents: ["public.audio"],
            description: "Waveform audio"),
        ContentTypeRecord("public.mpeg-4-audio", extensions: ["mp4", "mpg4"],
            mimeTypes: ["audio/mp4", "audio/mp4a-latm"], parents: ["public.audio"], description: "MPEG-4 audio"),
        ContentTypeRecord("com.apple.m4a-audio", extensions: ["m4a"], mimeTypes: ["audio/x-m4a"],
            parents: ["public.mpeg-4-audio"], description: "Apple MPEG-4 audio"),
        ContentTypeRecord("public.aifc-audio", extensions: ["aifc"], parents: ["public.audio"],
            description: "AIFF-C audio"),
        ContentTypeRecord("public.aiff-audio", extensions: ["aiff", "aif"], mimeTypes: ["audio/aiff", "audio/x-aiff"],
            parents: ["public.aifc-audio"], description: "AIFF audio"),
        ContentTypeRecord("public.archive", description: "file archive"),
        ContentTypeRecord("com.pkware.zip-archive", parents: ["public.archive", "public.data"],
            description: "PKZip archive"),
        ContentTypeRecord("public.zip-archive", extensions: ["zip"],
            mimeTypes: ["application/zip", "application/x-zip-compressed"], parents: ["com.pkware.zip-archive"],
            description: "Zip archive"),
        ContentTypeRecord("org.gnu.gnu-zip-archive", extensions: ["gz", "gzip"],
            mimeTypes: ["application/x-gzip", "application/gzip"], parents: ["public.archive", "public.data"],
            description: "GZip archive"),
        ContentTypeRecord("public.bzip2-archive", extensions: ["bz2", "bz"],
            mimeTypes: [
                "application/x-bzip2", "application/x-bzip", "application/bzip2", "application/bzip", "application/x-bz2",
            ], parents: ["public.archive", "public.data"], description: "Bzip2 archive"),
        ContentTypeRecord("org.gnu.gnu-tar-archive", extensions: ["gtar"], mimeTypes: ["application/x-gtar"],
            parents: ["public.archive", "public.data"], description: "GNU tar archive"),
        ContentTypeRecord("public.tar-archive", extensions: ["tar"],
            mimeTypes: ["application/x-tar", "application/tar"], parents: ["org.gnu.gnu-tar-archive"],
            description: "tar archive"),
        ContentTypeRecord("org.gnu.gnu-zip-tar-archive", extensions: ["tgz"], parents: ["org.gnu.gnu-zip-archive"],
            description: "gzip tar archive"),
        ContentTypeRecord("public.disk-image", parents: ["public.archive"], description: "disk image"),
        ContentTypeRecord("public.font", parents: ["public.data"], description: "font"),
        ContentTypeRecord("public.database", description: "database"),
        ContentTypeRecord("public.spreadsheet", description: "Spreadsheet"),
        ContentTypeRecord("public.presentation", description: "presentation"),
        ContentTypeRecord("public.message", description: "message"),
        ContentTypeRecord("public.email-message", parents: ["public.message"], description: "email message"),
        ContentTypeRecord("public.contact", description: "contact information"),
        ContentTypeRecord("public.vcard", extensions: ["vcf", "vcard"],
            mimeTypes: ["text/vcard", "text/directory", "text/x-vcard"], parents: ["public.contact", "public.text"],
            description: "electronic business card"),
        ContentTypeRecord("public.calendar-event", description: "calendar event"),
    ]

    /// Each identifier's record, by its index in ``records``.
    static let byIdentifier: [String: Int] = {
        var index: [String: Int] = [:]
        for (offset, record) in records.enumerated() { index[record.identifier] = offset }
        return index
    }()

    /// Each lowercased extension's record: the first that lists it.
    static let byExtension: [String: Int] = {
        var index: [String: Int] = [:]
        for (offset, record) in records.enumerated() {
            for name in record.extensions where index[name] == nil { index[name] = offset }
        }
        return index
    }()

    /// Each lowercased MIME type's record: the first that lists it.
    static let byMIMEType: [String: Int] = {
        var index: [String: Int] = [:]
        for (offset, record) in records.enumerated() {
            for name in record.mimeTypes where index[name.lowercased()] == nil { index[name.lowercased()] = offset }
        }
        return index
    }()

    /// The record declaring `identifier`, if this table has one.
    static func record(_ identifier: String) -> ContentTypeRecord? {
        byIdentifier[identifier].map { records[$0] }
    }

    /// The record an extension names, matched without regard to case, if any.
    static func record(forExtension name: String) -> ContentTypeRecord? {
        byExtension[name.lowercased()].map { records[$0] }
    }

    /// The record a MIME type names, matched without regard to case, if any.
    static func record(forMIMEType name: String) -> ContentTypeRecord? {
        byMIMEType[name.lowercased()].map { records[$0] }
    }

    /// Every identifier the type `identifier` conforms to, through its declared
    /// parents and theirs, `identifier` itself excluded. An identifier the
    /// table does not declare has none.
    static func ancestors(of identifier: String) -> Set<String> {
        var found: Set<String> = []
        var pending = record(identifier)?.parents ?? []
        while let next = pending.popLast() {
            guard found.insert(next).inserted else { continue }
            pending.append(contentsOf: record(next)?.parents ?? [])
        }
        return found
    }
}
