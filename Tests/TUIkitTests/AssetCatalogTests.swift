//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AssetCatalogTests.swift
//
//  `Color(_:bundle:)` and `Image(_:bundle:)` read an asset catalogue: the
//  uncompiled `.xcassets` folder `swift build` copies into a resource bundle,
//  everywhere, and on macOS through `TUIkitAppKit` the `Assets.car` Xcode
//  compiles. The fixtures are `__Fixtures__/AssetCatalog`: `Source.xcassets`
//  (a colour set with a dark variant written in hexadecimal, an image set at
//  1x and 2x) and the `Assets.car` `actool` compiled from it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

#if canImport(AppKit)
    import TUIkitAppKit
#endif

/// A directory made for one test, removed with it.
private final class TemporaryBundle {
    let path: String

    init() throws {
        path = NSTemporaryDirectory() + "tuikit-assets-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("__Fixtures__/AssetCatalog")

    /// A bundle holding the fixture catalogue, uncompiled, as `swift build`
    /// lays a resource bundle out: flat, the folder at the top.
    static func uncompiled() throws -> (TemporaryBundle, Bundle) {
        let made = try TemporaryBundle()
        try FileManager.default.copyItem(
            atPath: fixtures.appendingPathComponent("Source.xcassets").path,
            toPath: (made.path as NSString).appendingPathComponent("Assets.xcassets"))
        return (made, try #require(Bundle(path: made.path)))
    }

    func write(_ text: String, to relative: String) throws {
        let full = (path as NSString).appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: full, atomically: true, encoding: .utf8)
    }
}

private func components(_ color: Color) -> [Float] {
    let resolved = color.resolve(in: EnvironmentValues())
    return [resolved.red, resolved.green, resolved.blue, resolved.opacity].map { ($0 * 255).rounded() }
}

@Suite("Asset catalogues")
struct AssetCatalogTests {
    @Test("A colour set's light and dark colours are read, the dark one written in hexadecimal")
    func aColourSetsTwoColours() throws {
        let (made, bundle) = try TemporaryBundle.uncompiled()
        defer { withExtendedLifetime(made) {} }
        let set = try #require(AssetCatalog.colorSet(named: "Brand", in: bundle))
        #expect(components(set.color(for: .light)) == [204, 102, 51, 255])
        #expect(components(set.color(for: .dark)) == [16, 128, 255, 255])
    }

    @Test("Color(_:bundle:) is the set's colour for the default colour scheme, and clear for a name it lacks")
    @MainActor
    func theInitialiser() throws {
        let (made, bundle) = try TemporaryBundle.uncompiled()
        defer { withExtendedLifetime(made) {} }
        let set = try #require(AssetCatalog.colorSet(named: "Brand", in: bundle))
        #expect(Color("Brand", bundle: bundle) == set.color(for: EnvironmentValues().colorScheme))
        #expect(Color("NoSuchColour", bundle: bundle) == .clear, "SwiftUI's missing colour is #00000000")
    }

    @Test("Components are read as Xcode writes them: floating point, 8-bit, hexadecimal, a grey, a system colour")
    func componentSpellings() {
        let float = AssetCatalog.color(from: [
            "color-space": "srgb", "components": ["red": "1.000", "green": "0.500", "blue": "0.000", "alpha": "0.500"],
        ])
        #expect(float.map(components) == [255, 128, 0, 128])
        let eightBit = AssetCatalog.color(from: [
            "color-space": "srgb", "components": ["red": "204", "green": "102", "blue": "51", "alpha": "1.000"],
        ])
        #expect(eightBit.map(components) == [204, 102, 51, 255])
        // Digits alone are 8-bit whatever their size, as actool reads them
        // (measured): "1" is 1/255, beside a float or an 8-bit component, in
        // the alpha too; a JSON number is taken as it is.
        let small = AssetCatalog.color(from: [
            "color-space": "srgb", "components": ["red": "128", "green": "1", "blue": "0", "alpha": "1.000"],
        ])
        #expect(small.map(components) == [128, 1, 0, 255])
        let mixed = AssetCatalog.color(from: [
            "color-space": "srgb", "components": ["red": "1", "green": "0.500", "blue": "0", "alpha": "128"],
        ])
        #expect(mixed.map(components) == [1, 128, 0, 128])
        let numbers = AssetCatalog.color(from: [
            "color-space": "srgb", "components": ["red": 1.0, "green": 0.5, "blue": 0.0, "alpha": 1.0],
        ])
        #expect(numbers.map(components) == [255, 128, 0, 255])
        let grey = AssetCatalog.color(from: [
            "color-space": "gray-gamma-22", "components": ["white": "0.500", "alpha": "1.000"],
        ])
        #expect(grey.map(components) == components(Color(white: 0.5)))
        #expect(AssetCatalog.color(from: ["platform": "osx", "reference": "systemRedColor"]) == .red)
        #expect(AssetCatalog.color(from: ["platform": "osx", "reference": "unknownColor"]) == nil)
    }

    /// The names `actool` gives (measured, Xcode 26, `assetutil --info`):
    /// `Spaced/Inner`, `Spaced/Deep` and `Spaced/Ns2/Deeper` under folders
    /// that provide a namespace, plain `Leaf` and `Lone` under ones that do
    /// not (with a `Contents.json` and without), and the first of two `Leaf`s.
    @Test("A set is named as actool names it: under the folders that provide a namespace, and no others")
    func namesInFolders() throws {
        let made = try TemporaryBundle()
        func set(_ green: String) -> String {
            """
            {"colors": [{"idiom": "universal", "color": {"color-space": "srgb",
              "components": {"red": "0.000", "green": "\(green)", "blue": "0.000", "alpha": "1.000"}}}]}
            """
        }
        let namespace = #"{"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": true}}"#
        let plain = #"{"info": {"author": "xcode", "version": 1}}"#
        try made.write(namespace, to: "Assets.xcassets/Spaced/Contents.json")
        try made.write(set("1.000"), to: "Assets.xcassets/Spaced/Inner.colorset/Contents.json")
        try made.write(set("1.000"), to: "Assets.xcassets/Spaced/Plain2/Deep.colorset/Contents.json")
        try made.write(namespace, to: "Assets.xcassets/Spaced/Ns2/Contents.json")
        try made.write(set("1.000"), to: "Assets.xcassets/Spaced/Ns2/Deeper.colorset/Contents.json")
        try made.write(plain, to: "Assets.xcassets/Plain/Contents.json")
        try made.write(set("0.500"), to: "Assets.xcassets/Plain/Leaf.colorset/Contents.json")
        try made.write(set("0.250"), to: "Assets.xcassets/Other/Leaf.colorset/Contents.json")
        try made.write(set("1.000"), to: "Assets.xcassets/Bare/Lone.colorset/Contents.json")
        let bundle = try #require(Bundle(path: made.path))

        for name in ["Spaced/Inner", "Spaced/Deep", "Spaced/Ns2/Deeper", "Lone"] {
            #expect(AssetCatalog.colorSet(named: name, in: bundle)?.any == Color(.sRGB, red: 0, green: 1, blue: 0), "\(name)")
        }
        for name in ["Inner", "Deep", "Deeper", "Ns2/Deeper", "Spaced/Plain2/Deep", "Plain/Leaf", "Bare/Lone", "Missing"] {
            #expect(AssetCatalog.colorSet(named: name, in: bundle) == nil, "\(name) is not a name actool gives")
        }
        #expect(
            AssetCatalog.colorSet(named: "Leaf", in: bundle)?.any == Color(.sRGB, red: 0, green: 0.25, blue: 0),
            "not the first Leaf in name order")
    }

    @Test("An image set draws its largest picture at the scale it was made for")
    @MainActor
    func anImageSetsLargestPicture() throws {
        let (made, bundle) = try TemporaryBundle.uncompiled()
        defer { withExtendedLifetime(made) {} }
        let file = try #require(AssetCatalog.imageFile(named: "Logo", in: bundle, for: .light))
        #expect((file.path as NSString).lastPathComponent == "logo@2x.png")
        #expect(file.scale == 2)
        let image = Image("Logo", bundle: bundle)
        #expect(image.content == .raster(.file(file.path)))
        #expect(image.decoded?.pointSizing == .scale(2), "the 2x picture would draw twice its size")
        // Drawn out once, and the same object every frame, so a memo sees one picture.
        #expect(Image("Logo", bundle: bundle).decoded === image.decoded)
        let pixels = try #require(image.decoded).pixels
        #expect(pixels.width == 8 && pixels.height == 4)
    }

    @Test("A name no catalogue has falls back to a plain resource file, then to the missing file")
    @MainActor
    func plainFilesStillWork() throws {
        let made = try TemporaryBundle()
        try made.write("not really a picture", to: "plain.png")
        let bundle = try #require(Bundle(path: made.path))
        let plain = Image("plain", bundle: bundle)
        guard case .raster(.file(let path)) = plain.content else {
            Issue.record("not a file image: \(plain.content)")
            return
        }
        #expect((path as NSString).lastPathComponent == "plain.png")
        #expect(Image("absent", bundle: bundle).content == .raster(.file("absent")))
    }

    #if canImport(AppKit)
        /// A bundle as Xcode builds one, with the compiled catalogue in its
        /// resources — a name there and in no uncompiled catalogue is found by
        /// `TUIkitAppKit`'s initialisers, which every file of this test target
        /// sees (it links `TUIkitAppKit`).
        @Test("On macOS a compiled catalogue is read through AppKit, its dark colour chosen as TUIkit chooses")
        @MainActor
        func aCompiledCatalogue() throws {
            let made = try TemporaryBundle()
            let resources = (made.path as NSString).appendingPathComponent("Contents/Resources")
            try FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                atPath: TemporaryBundle.fixtures.appendingPathComponent("Assets.car").path,
                toPath: (resources as NSString).appendingPathComponent("Assets.car"))
            try made.write(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0"><dict>
                <key>CFBundleIdentifier</key><string>tuikit.tests.\(UUID().uuidString)</string>
                </dict></plist>
                """, to: "Contents/Info.plist")
            let bundle = try #require(Bundle(path: made.path))
            #expect(AssetCatalog.colorSet(named: "Brand", in: bundle) == nil, "precondition: nothing uncompiled")

            let expected: [Float] = EnvironmentValues().colorScheme == .dark ? [16, 128, 255, 255] : [204, 102, 51, 255]
            #expect(components(Color("Brand", bundle: bundle)) == expected)
            #expect(Color("NoSuchColour", bundle: bundle) == .clear)

            let image = Image("Logo", bundle: bundle)
            let decoded = try #require(image.decoded, "the compiled image was not found")
            #expect(decoded.pointSizing == .scale(2), "not the largest picture, at its scale")
            #expect(decoded.pixels.width == 8 && decoded.pixels.height == 4)
            #expect(Image("Logo", bundle: bundle).content == image.content, "a new picture every frame")
        }
    #endif
}
