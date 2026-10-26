//  🖥️ TUI — A Terminal UI framework for Swift
//  AssetCatalogTests.swift
//
//  `Color(_:bundle:)` and `Image(_:bundle:)` read an asset catalogue: the
//  uncompiled `.xcassets` folder `swift build` copies into a resource bundle,
//  everywhere, and on macOS through `TUIAppKit` the `Assets.car` Xcode
//  compiles. The fixtures are `__Fixtures__/AssetCatalog`: `Source.xcassets`
//  (a colour set with a dark variant written in hexadecimal, an image set at
//  1x and 2x) and the `Assets.car` `actool` compiled from it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIBitmaps
@testable import TUIBitmapsTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

#if canImport(AppKit)
    import AppKit
    @testable import TUIAppKit
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
    components(color, in: EnvironmentValues())
}

/// `color` drawn in an environment pinned to `scheme`.
private func components(_ color: Color, in scheme: ColorScheme) -> [Float] {
    var environment = EnvironmentValues()
    environment.colorScheme = scheme
    return components(color, in: environment)
}

private func components(_ color: Color, in environment: EnvironmentValues) -> [Float] {
    let resolved = color.resolve(in: environment)
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

    @Test("Color(_:bundle:) keeps both of a set's colours and draws the one for the scheme where it is drawn")
    @MainActor
    func theInitialiser() throws {
        let (made, bundle) = try TemporaryBundle.uncompiled()
        defer { withExtendedLifetime(made) {} }
        let brand = Color("Brand", bundle: bundle)
        guard case .lightDark = brand.value else {
            Issue.record("not chosen where it is drawn: \(brand)")
            return
        }
        #expect(components(brand, in: .light) == [204, 102, 51, 255])
        #expect(components(brand, in: .dark) == [16, 128, 255, 255])
        #expect(brand.rgbComponents! == (204, 102, 51), "a body measures the light colour")
        #expect(Color("Brand", bundle: bundle) == brand, "the same set is the same colour every frame")
        #expect(Color("NoSuchColour", bundle: bundle) == .clear, "SwiftUI's missing colour is #00000000")
    }

    /// A `Color` keeps one alpha, so two variants of different alphas cannot
    /// wait to be chosen where they are drawn (decisions B-D6M-4).
    @Test("A set whose colours differ in opacity is chosen when made, by the default colour scheme")
    @MainActor
    func twoAlphasChooseWhenMade() throws {
        let made = try TemporaryBundle()
        try made.write(
            """
            {"colors": [
              {"idiom": "universal", "color": {"color-space": "srgb",
                "components": {"red": "1.000", "green": "0.000", "blue": "0.000", "alpha": "1.000"}}},
              {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "color": {"color-space": "srgb",
                "components": {"red": "0.000", "green": "0.000", "blue": "1.000", "alpha": "0.500"}}}]}
            """, to: "Assets.xcassets/Faded.colorset/Contents.json")
        let bundle = try #require(Bundle(path: made.path))
        let set = try #require(AssetCatalog.colorSet(named: "Faded", in: bundle))
        #expect(set.drawn == nil)
        #expect(Color("Faded", bundle: bundle) == set.color(for: EnvironmentValues().colorScheme))
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
        #expect(image.sourcedRaster?.source == .file(file.path))
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
        guard case .file(let path) = plain.sourcedRaster?.source else {
            Issue.record("not a file image: \(plain.content)")
            return
        }
        #expect((path as NSString).lastPathComponent == "plain.png")
        #expect(Image("absent", bundle: bundle).sourcedRaster?.source == .file("absent"))
    }

    #if canImport(AppKit)
        /// A bundle as Xcode builds one, with the compiled catalogue in its
        /// resources — a name there and in no uncompiled catalogue is found by
        /// `TUIAppKit`'s initialisers, which every file of this test target
        /// sees (it links `TUIAppKit`).
        @Test("On macOS a compiled catalogue is read through AppKit, both its colours kept as TUI keeps them")
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

            let brand = Color("Brand", bundle: bundle)
            #expect(components(brand, in: .light) == [204, 102, 51, 255])
            #expect(components(brand, in: .dark) == [16, 128, 255, 255], "not chosen where it is drawn")
            #expect(brand == Color("Brand", bundle: try TemporaryBundle.uncompiled().1), "a pair is one colour")
            #expect(Color("NoSuchColour", bundle: bundle) == .clear)
            // A body names its colour every frame: AppKit is asked once.
            for _ in 0..<3 {
                _ = Color("Brand", bundle: bundle)
                _ = Color("NoSuchColour", bundle: bundle)
            }
            #expect(CompiledCatalog.colorLookupCount(named: "Brand", in: bundle) == 1)
            #expect(CompiledCatalog.colorLookupCount(named: "NoSuchColour", in: bundle) == 1, "a miss is asked again")

            let image = Image("Logo", bundle: bundle)
            let decoded = try #require(image.decoded, "the compiled image was not found")
            #expect(decoded.pointSizing == .scale(2), "not the largest picture, at its scale")
            #expect(decoded.pixels.width == 8 && decoded.pixels.height == 4)
            #expect(Image("Logo", bundle: bundle).content == image.content, "a new picture every frame")
        }

        @Test("A dynamic NSColor keeps both its appearances' colours and draws the one for the scheme")
        func aDynamicNSColor() {
            let dynamic = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
                    : NSColor(srgbRed: 0.9, green: 0.8, blue: 0.7, alpha: 1)
            }
            let colour = Color(nsColor: dynamic)
            #expect(components(colour, in: .light) == [230, 204, 179, 255])
            #expect(components(colour, in: .dark) == [26, 51, 77, 255])
            // One that is the same under both is a plain colour.
            #expect(Color(nsColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) == .rgb(255, 0, 0))
        }
    #endif
}
