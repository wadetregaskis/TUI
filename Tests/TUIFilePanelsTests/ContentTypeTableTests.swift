//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentTypeTableTests.swift
//
//  The table behind Linux's `UTType` says what UniformTypeIdentifiers says,
//  checked where both exist; and, where only the table does, the type built
//  on it answers as Apple's would.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFilePanels

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers

    /// Every record of the table, held to UniformTypeIdentifiers on the machine
    /// the tests run on: a record that drifted from Apple's declaration would
    /// type a file one way on macOS and another on Linux.
    @Suite("Content type table matches UniformTypeIdentifiers")
    struct ContentTypeTableTests {
        @Test("Every record names a type Apple declares, with its extensions and MIME types")
        func recordsMatchDeclarations() throws {
            for record in ContentTypeTable.records {
                let type = try #require(UTType(record.identifier), "\(record.identifier) is not declared")
                #expect(
                    record.extensions == (type.tags[.filenameExtension] ?? []),
                    "\(record.identifier)'s extensions")
                #expect(record.mimeTypes == (type.tags[.mimeType] ?? []), "\(record.identifier)'s MIME types")
            }
        }

        @Test("A record conforms to exactly the table's types Apple's conforms to")
        func conformancesMatch() throws {
            let known = Set(ContentTypeTable.records.map(\.identifier))
            for record in ContentTypeTable.records {
                let type = try #require(UTType(record.identifier))
                let apple = Set(type.supertypes.map(\.identifier)).intersection(known)
                #expect(ContentTypeTable.ancestors(of: record.identifier) == apple, "\(record.identifier)")
            }
        }

        @Test("An extension or MIME type names the record Apple's names")
        func lookupsMatch() {
            for record in ContentTypeTable.records {
                for name in record.extensions {
                    #expect(
                        ContentTypeTable.record(forExtension: name)?.identifier
                            == UTType(filenameExtension: name)?.identifier, "extension \(name)")
                }
                for name in record.mimeTypes {
                    #expect(
                        ContentTypeTable.record(forMIMEType: name)?.identifier
                            == UTType(mimeType: name)?.identifier, "MIME type \(name)")
                }
            }
        }

        @Test("Lookups ignore case, as Apple's do")
        func lookupsIgnoreCase() {
            #expect(ContentTypeTable.record(forExtension: "PNG")?.identifier == "public.png")
            #expect(UTType(filenameExtension: "PNG")?.identifier == "public.png")
            #expect(ContentTypeTable.record(forMIMEType: "Image/PNG")?.identifier == "public.png")
        }
    }
#else
    /// The type Linux uses in UniformTypeIdentifiers' place, answering as
    /// Apple's does for the same questions (checked against Apple's on macOS
    /// by the session notes' O10/probe/shim, which compiles this type there).
    @Suite("UTType where UniformTypeIdentifiers is absent")
    struct PortableUTTypeTests {
        @Test("An extension names its declared type, without regard to case")
        func extensionNamesDeclaredType() {
            #expect(UTType(filenameExtension: "png") == .png)
            #expect(UTType(filenameExtension: "PNG") == .png)
            #expect(UTType(filenameExtension: "md") == UTType("net.daringfireball.markdown"))
            #expect(UTType(filenameExtension: "") == nil)
        }

        @Test("Conformance walks the declared parents")
        func conformance() {
            #expect(UTType.png.conforms(to: .image))
            #expect(UTType.png.conforms(to: .data) && UTType.png.conforms(to: .item))
            #expect(!UTType.png.conforms(to: .text))
            #expect(UTType.folder.conforms(to: .directory) && !UTType.directory.conforms(to: .folder))
            #expect(UTType.png.isSubtype(of: .image) && UTType.image.isSupertype(of: .png))
            #expect(!UTType.png.isSubtype(of: .png))
        }

        @Test("An unknown extension gives a dynamic type conforming to its supertype")
        func dynamicTypes() throws {
            let other = try #require(UTType(filenameExtension: "foo"))
            #expect(other.isDynamic && other.conforms(to: .data) && other.preferredFilenameExtension == "foo")
            let note = try #require(UTType(filenameExtension: "note", conformingTo: .text))
            #expect(note.conforms(to: .text) && note.preferredFilenameExtension == "note" && note != other)
            #expect(UTType(filenameExtension: "png", conformingTo: .text)?.isDynamic == true)
        }

        @Test("An exported type conforms to its parent and has no extension")
        func exportedTypes() {
            let document = UTType(exportedAs: "com.example.doc", conformingTo: .json)
            #expect(document.conforms(to: .json) && document.conforms(to: .text))
            #expect(document.isDeclared && !document.isDynamic && document.preferredFilenameExtension == nil)
            #expect(UTType(exportedAs: "public.png") == .png)
        }

        @Test("A type is coded as its identifier")
        func coding() throws {
            let document = UTType(exportedAs: "com.example.doc")
            let data = try JSONEncoder().encode([UTType.png, document])
            #expect(String(bytes: data, encoding: .utf8) == #"["public.png","com.example.doc"]"#)
            #expect(try JSONDecoder().decode([UTType].self, from: data) == [.png, document])
        }
    }
#endif
