//  🖥️ TUI — A Terminal UI framework for Swift
//  FileWrapper+Portable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Foundation's `FileWrapper` is `NSFileWrapper`, an Objective-C class, and
// swift-corelibs-foundation does not provide one at all (Swift 6.3.3's static
// Linux SDK: "cannot find 'FileWrapper' in scope"). Where Objective-C is there,
// so is Foundation's, and this file declares nothing. If corelibs ever ships
// one, the name turns ambiguous in an app's code, and this file goes.
#if !canImport(ObjectiveC)

    import Foundation

    /// A representation of a node (a file, directory, or symbolic link) in the
    /// file system — Foundation's `FileWrapper`, for the platforms whose
    /// Foundation has none.
    ///
    /// Its Swift surface is Foundation's, so a ``FileDocument`` compiles
    /// unchanged on both, and it behaves as Foundation's does (measured on
    /// macOS 15.8; `FileWrapperTests` pass against both), with four
    /// exceptions:
    ///
    /// - `regularFileContents`, `fileWrappers` and `symbolicLinkDestinationURL`
    ///   answer `nil` for a wrapper of another kind, where Foundation's raises
    ///   an exception, and a child with no name is added as Untitled, where
    ///   Foundation's raises one too: a framework that draws in a terminal does
    ///   not take the process down for it.
    /// - ``read(from:options:)`` always reads, where Foundation's skips a file it
    ///   thinks has not changed.
    /// - A directory written over one that exists, not atomically, fails and
    ///   leaves it, where Foundation's fails having removed it.
    /// - Changing a child's ``preferredFilename`` leaves its key in its parent as
    ///   it was (the sequence raises an exception in Foundation's).
    ///
    /// It has no `serializedRepresentation`: that is an RTFD pasteboard format,
    /// meaningless without AppKit, so code that uses it does not compile.
    open class FileWrapper {
        /// Reading options for a file wrapper.
        public struct ReadingOptions: OptionSet, Sendable {
            public let rawValue: UInt

            public init(rawValue: UInt) {
                self.rawValue = rawValue
            }

            /// Reads a file's contents at once, rather than when they are asked for.
            public static let immediate = Self(rawValue: 1 << 0)

            /// Reads a file's contents without mapping it, which this type never
            /// does, so it changes nothing: it is here for the code that says so.
            public static let withoutMapping = Self(rawValue: 1 << 1)
        }

        /// Writing options for a file wrapper.
        public struct WritingOptions: OptionSet, Sendable {
            public let rawValue: UInt

            public init(rawValue: UInt) {
                self.rawValue = rawValue
            }

            /// Writes beside the destination and moves into place, replacing what
            /// is there. Without it, a directory or a symbolic link written over
            /// something that exists fails.
            public static let atomic = Self(rawValue: 1 << 0)

            /// Sets each descendant's ``FileWrapper/filename`` to the name it was
            /// written under, if the write succeeds.
            public static let withNameUpdating = Self(rawValue: 1 << 1)
        }

        /// What a wrapper is, and what it holds.
        private enum Node {
            /// A file: its contents, or where to read them when they are asked for.
            case regular(Data?, source: URL?)
            case directory([String: FileWrapper])
            case symbolicLink(URL)
        }

        private var node: Node

        /// The name this wrapper prefers, in a directory wrapper or when written.
        open var preferredFilename: String?

        /// The name this wrapper was last read from or written to, if any.
        open var filename: String?

        /// The attributes of the file: the keys of `FileAttributeKey`, as strings.
        /// Those read with the file; of these, a write applies the POSIX
        /// permissions and the modification date.
        open var fileAttributes: [String: Any] = [:]

        // MARK: Creating

        /// Creates a file wrapper from the node at `url`: a regular file, a
        /// directory with a wrapper for everything in it, or a symbolic link,
        /// which is not followed.
        ///
        /// - Parameters:
        ///   - url: The node to read.
        ///   - options: `.immediate` reads the contents of regular files now.
        public init(url: URL, options: ReadingOptions = []) throws {
            self.node = try Self.readNode(at: url, options: options)
            self.filename = url.lastPathComponent
            self.preferredFilename = url.lastPathComponent
            self.fileAttributes = Self.attributes(at: url)
        }

        /// Creates a directory wrapper holding `childrenByPreferredName`, each
        /// child taking its key as its preferred name.
        public init(directoryWithFileWrappers childrenByPreferredName: [String: FileWrapper]) {
            self.node = .directory(childrenByPreferredName)
            for (key, child) in childrenByPreferredName {
                child.preferredFilename = key
            }
        }

        /// Creates a regular-file wrapper with `contents`.
        public init(regularFileWithContents contents: Data) {
            self.node = .regular(contents, source: nil)
        }

        /// Creates a symbolic-link wrapper pointing at `url`.
        public init(symbolicLinkWithDestinationURL url: URL) {
            self.node = .symbolicLink(url)
        }

        // MARK: Querying

        /// Whether this is a directory wrapper.
        open var isDirectory: Bool {
            if case .directory = node { return true }
            return false
        }

        /// Whether this is a regular-file wrapper.
        open var isRegularFile: Bool {
            if case .regular = node { return true }
            return false
        }

        /// Whether this is a symbolic-link wrapper.
        open var isSymbolicLink: Bool {
            if case .symbolicLink = node { return true }
            return false
        }

        /// The contents of a regular-file wrapper; `nil` for another kind, or for a
        /// file that could not be read when they were asked for.
        open var regularFileContents: Data? {
            guard case .regular(let contents, let source) = node else { return nil }
            if let contents { return contents }
            guard let source, let read = try? Data(contentsOf: source) else { return nil }
            node = .regular(read, source: source)
            return read
        }

        /// The children of a directory wrapper, by key; `nil` for another kind.
        open var fileWrappers: [String: FileWrapper]? {
            guard case .directory(let children) = node else { return nil }
            return children
        }

        /// Where a symbolic-link wrapper points; `nil` for another kind.
        open var symbolicLinkDestinationURL: URL? {
            guard case .symbolicLink(let destination) = node else { return nil }
            return destination
        }

        /// The key `child` is held under in this directory wrapper, if it is.
        open func keyForChildFileWrapper(_ child: FileWrapper) -> String? {
            fileWrappers?.first { $0.value === child }?.key
        }

        // MARK: Children

        /// Adds `child` to this directory wrapper, under its preferred name, or
        /// under a key made from it if that is taken, and returns the key.
        /// Nothing happens to a wrapper of another kind, which answers the name.
        @discardableResult
        open func addFileWrapper(_ child: FileWrapper) -> String {
            let name = child.preferredFilename ?? "Untitled"
            guard case .directory(var children) = node else { return name }
            let key = Self.unusedKey(for: name, in: children)
            children[key] = child
            node = .directory(children)
            return key
        }

        /// Adds a regular file with `data` to this directory wrapper, and returns
        /// its key.
        @discardableResult
        open func addRegularFile(withContents data: Data, preferredFilename fileName: String) -> String {
            let child = FileWrapper(regularFileWithContents: data)
            child.preferredFilename = fileName
            return addFileWrapper(child)
        }

        /// Removes `child` from this directory wrapper.
        open func removeFileWrapper(_ child: FileWrapper) {
            guard case .directory(var children) = node, let key = keyForChildFileWrapper(child) else { return }
            children[key] = nil
            node = .directory(children)
        }

        // MARK: Reading and writing

        /// Whether this wrapper holds what the node at `url` holds.
        open func matchesContents(of url: URL) -> Bool {
            guard let other = try? FileWrapper(url: url) else { return false }
            return matches(other)
        }

        /// Reads this wrapper's contents again, from the node at `url`, which may
        /// be of another kind now.
        open func read(from url: URL, options: ReadingOptions = []) throws {
            node = try Self.readNode(at: url, options: options)
            filename = url.lastPathComponent
            fileAttributes = Self.attributes(at: url)
        }

        /// Writes this wrapper to `url`.
        ///
        /// - Parameters:
        ///   - url: Where to write it, in a folder that exists.
        ///   - options: See ``WritingOptions``.
        ///   - originalContentsURL: Where the contents were read from, which
        ///     lets Foundation's copy rather than write. Not used here: every
        ///     wrapper holds its contents or knows where they are.
        open func write(to url: URL, options: WritingOptions = [], originalContentsURL: URL?) throws {
            if options.contains(.atomic) {
                let temporary = url.deletingLastPathComponent()
                    .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
                do {
                    try writeNode(to: temporary)
                    if FileManager.default.fileExists(atPath: url.path) {
                        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
                    } else {
                        try FileManager.default.moveItem(at: temporary, to: url)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: temporary)
                    throw error
                }
            } else {
                try writeNode(to: url)
            }
            if options.contains(.withNameUpdating) { updateChildrenNames() }
        }

        // MARK: Private

        /// `name`, or if it is taken, the key Foundation's makes of it.
        private static func unusedKey(for name: String, in children: [String: FileWrapper]) -> String {
            guard children[name] != nil else { return name }
            var count = 1
            while children["\(count)__#$!@%!#__\(name)"] != nil { count += 1 }
            return "\(count)__#$!@%!#__\(name)"
        }

        /// The node at `url`, as this type holds one.
        private static func readNode(at url: URL, options: ReadingOptions) throws -> Node {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory:
                var children: [String: FileWrapper] = [:]
                for name in try FileManager.default.contentsOfDirectory(atPath: url.path) {
                    children[name] = try FileWrapper(url: url.appendingPathComponent(name), options: options)
                }
                return .directory(children)
            case .typeSymbolicLink:
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                return .symbolicLink(URL(fileURLWithPath: destination))
            case .typeRegular:
                let contents = options.contains(.immediate) ? try Data(contentsOf: url) : nil
                return .regular(contents, source: url)
            default:
                // A pipe or a device: reading one may never end.
                throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }

        /// The node's attributes at `url`, spelled as Foundation's are.
        private static func attributes(at url: URL) -> [String: Any] {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return [:] }
            return Dictionary(uniqueKeysWithValues: attributes.map { ($0.key.rawValue, $0.value) })
        }

        /// Writes the node to `url`, with nothing atomic about it.
        private func writeNode(to url: URL) throws {
            switch node {
            case .regular:
                guard let contents = regularFileContents else {
                    throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
                }
                try contents.write(to: url)
            case .directory(let children):
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                for (key, child) in children {
                    try child.writeNode(to: url.appendingPathComponent(key))
                }
            case .symbolicLink(let destination):
                // `relativePath`, so that a relative destination stays relative.
                try FileManager.default.createSymbolicLink(
                    atPath: url.path, withDestinationPath: destination.relativePath)
                return  // A link's attributes would be its target's.
            }
            applyAttributes(to: url)
        }

        /// Applies what a write applies of ``fileAttributes``.
        private func applyAttributes(to url: URL) {
            var applied: [FileAttributeKey: Any] = [:]
            for key in [FileAttributeKey.posixPermissions, .modificationDate] {
                if let value = fileAttributes[key.rawValue] { applied[key] = value }
            }
            guard !applied.isEmpty else { return }
            try? FileManager.default.setAttributes(applied, ofItemAtPath: url.path)
        }

        /// Sets each descendant's ``filename`` to its key.
        private func updateChildrenNames() {
            guard case .directory(let children) = node else { return }
            for (key, child) in children {
                child.filename = key
                child.updateChildrenNames()
            }
        }

        /// Whether this wrapper and `other` hold the same.
        private func matches(_ other: FileWrapper) -> Bool {
            switch node {
            case .regular:
                return other.isRegularFile && regularFileContents == other.regularFileContents
            case .directory(let children):
                guard let others = other.fileWrappers, others.count == children.count else { return false }
                return children.allSatisfy { key, child in others[key].map(child.matches) ?? false }
            case .symbolicLink(let destination):
                return other.symbolicLinkDestinationURL?.relativePath == destination.relativePath
            }
        }
    }
#endif
