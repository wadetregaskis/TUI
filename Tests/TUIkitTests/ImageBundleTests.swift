//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageBundleTests.swift
//
//  `Image(_:bundle:)` and its labelled and decorative forms: a named image is
//  a plain image file among the bundle's resources.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation

@MainActor
@Suite("Named images in a bundle")
struct ImageBundleTests {

    @Test("A name finds the image file of that name, with or without its extension")
    func findsTheFile() throws {
        let fixture = try BitmapFixture(width: 4, height: 4)
        let bundle = try #require(Bundle(path: (fixture.path as NSString).deletingLastPathComponent))
        let found = URL(fileURLWithPath: fixture.path).resolvingSymlinksInPath().path

        func resolved(_ name: String) -> String {
            URL(fileURLWithPath: Image.resourcePath(named: name, in: bundle)).resolvingSymlinksInPath().path
        }
        #expect(resolved("fixture") == found)
        #expect(resolved("fixture.bmp") == found)
        #expect(Image.resourcePath(named: "missing", in: bundle) == "missing")
    }

    @Test("The labelled and decorative forms name the same image")
    func formsAgree() throws {
        let fixture = try BitmapFixture(width: 4, height: 4)
        let bundle = try #require(Bundle(path: (fixture.path as NSString).deletingLastPathComponent))
        let plain = Image("fixture", bundle: bundle)
        #expect(plain == Image("fixture", bundle: bundle, label: Text("A fixture")))
        #expect(plain == Image(decorative: "fixture", bundle: bundle))
        #expect(plain != Image("missing", bundle: bundle))
    }
}
