//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AssetCatalog.swift
//
//  An asset catalogue as `swift build` leaves it: the `.xcassets` folder,
//  copied into the resource bundle uncompiled, read as the JSON it is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

/// The named colours and images of the uncompiled asset catalogues a bundle
/// carries — `Assets.xcassets` copied as a resource.
///
/// Only Xcode compiles an asset catalogue (into `Assets.car`). `swift build`
/// copies the folder into the target's resource bundle as it is, measured with
/// `.process("Resources")`: `Name.colorset/Contents.json` and
/// `Name.imageset/Contents.json` beside the image files. So that is what a
/// SwiftPM app has, on every platform, and this reads it. A compiled
/// catalogue is read on macOS by `TUIkitAppKit`, through AppKit.
///
/// A catalogue is any `*.xcassets` folder at the top of the bundle's
/// resources. A set has the name `actool` gives it (measured, Xcode 26): its
/// own, under the names of the folders above it that provide a namespace
/// (`"provides-namespace": true` in the folder's `Contents.json`, which
/// Xcode's Provides Namespace checkbox writes), so `Colors/Brand` inside such
/// a folder and plain `Brand` inside any other. Where two sets share a name
/// the first in name order is found.
///
/// What is read is kept, by catalogue and name, for the process: a body that
/// names a colour reads it on every frame.
enum AssetCatalog {
    /// A colour set's colours: the one for any appearance, and the one for a
    /// dark appearance where the set has one.
    struct ColorSet: Equatable {
        let any: Color
        let dark: Color?
        /// The set as one colour that chooses its variant where it is drawn
        /// (`Color.lightDark(light:dark:)`), or `nil` where its two cannot be
        /// kept so and one is chosen when the colour is made.
        let drawn: Color?

        init(any: Color, dark: Color?) {
            self.any = any
            self.dark = dark
            drawn = Color.lightDark(light: any, dark: dark ?? any)
        }

        /// The colour for `scheme`.
        func color(for scheme: ColorScheme) -> Color {
            scheme == .dark ? dark ?? any : any
        }
    }

    /// An image set's file: the largest of its pictures TUIkit can decode, and
    /// the scale it was drawn for.
    struct ImageFile: Equatable {
        let path: String
        let scale: Double
    }

    // MARK: - Lookup

    /// The colour set `name` in `bundle`'s catalogues, or `nil` where none has
    /// one.
    static func colorSet(named name: String, in bundle: Bundle) -> ColorSet? {
        cached(.color, name, bundle) { folder in
            parseColorSet(at: folder).map(Entry.color)
        }.flatMap { if case .color(let set) = $0 { set } else { nil } }
    }

    /// The image file `name` in `bundle`'s catalogues draws, in `scheme`, or
    /// `nil` where none has a decodable one.
    static func imageFile(named name: String, in bundle: Bundle, for scheme: ColorScheme) -> ImageFile? {
        let entry = cached(.image, name, bundle) { folder in
            parseImageSet(at: folder).map(Entry.image)
        }
        guard case .image(let set) = entry else { return nil }
        return scheme == .dark ? set.dark ?? set.any : set.any ?? set.dark
    }

    // MARK: - The cache

    private enum Kind: String {
        case color = "colorset"
        case image = "imageset"
    }

    private struct ImageSet: Equatable {
        let any: ImageFile?
        let dark: ImageFile?
    }

    private enum Entry: Equatable {
        case color(ColorSet)
        case image(ImageSet)
        case missing
    }

    private struct Key: Hashable {
        let bundlePath: String
        let kind: String
        let name: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [Key: Entry] = [:]

    /// The parsed set `name` of `kind` in `bundle`, read once.
    private static func cached(
        _ kind: Kind, _ name: String, _ bundle: Bundle, parse: (String) -> Entry?
    ) -> Entry? {
        let key = Key(bundlePath: bundle.bundlePath, kind: kind.rawValue, name: name)
        if let known = lock.withLock({ entries[key] }) {
            return known == .missing ? nil : known
        }
        let entry = folder(of: kind, named: name, in: bundle).flatMap(parse) ?? .missing
        lock.withLock { entries[key] = entry }
        return entry == .missing ? nil : entry
    }

    /// The `.colorset` / `.imageset` folder `actool` would name `name`.
    private static func folder(of kind: Kind, named name: String, in bundle: Bundle) -> String? {
        let bundlePath = bundle.bundlePath
        if let index = lock.withLock({ names[bundlePath] }) {
            return index[NameKey(kind: kind.rawValue, name: name)]
        }
        var index: [NameKey: String] = [:]
        for catalog in catalogs(in: bundle) {
            indexSets(in: catalog, namespace: "", into: &index)
        }
        lock.withLock { names[bundlePath] = index }
        return index[NameKey(kind: kind.rawValue, name: name)]
    }

    /// A set's kind and the name `actool` gives it.
    private struct NameKey: Hashable {
        let kind: String
        let name: String
    }

    /// Each bundle's sets by name, read once, by bundle path.
    nonisolated(unsafe) private static var names: [String: [NameKey: String]] = [:]

    /// Names every colour and image set under `folder`, in name order, each
    /// under `namespace` (the namespaces of the folders above it, each with a
    /// trailing `/`): a folder that provides a namespace adds its own name for
    /// what is inside it, any other adds nothing. The first set of a name is
    /// kept.
    private static func indexSets(in folder: String, namespace: String, into index: inout [NameKey: String]) {
        let manager = FileManager.default
        for item in ((try? manager.contentsOfDirectory(atPath: folder)) ?? []).sorted() {
            let path = (folder as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let kind = (item as NSString).pathExtension
            if kind == Kind.color.rawValue || kind == Kind.image.rawValue {
                let key = NameKey(kind: kind, name: namespace + (item as NSString).deletingPathExtension)
                if index[key] == nil { index[key] = path }
            } else {
                let properties = contents(of: path)?["properties"] as? [String: Any]
                let providesNamespace = properties?["provides-namespace"] as? Bool ?? false
                indexSets(in: path, namespace: providesNamespace ? namespace + item + "/" : namespace, into: &index)
            }
        }
    }

    /// Every `*.xcassets` folder at the top of `bundle`'s resources, sorted
    /// so the search order does not depend on the file system's.
    private static func catalogs(in bundle: Bundle) -> [String] {
        var roots = [bundle.bundlePath]
        if let resources = bundle.resourcePath, resources != bundle.bundlePath { roots.append(resources) }
        return roots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
                .filter { ($0 as NSString).pathExtension == "xcassets" }
                .sorted()
                .map { (root as NSString).appendingPathComponent($0) }
        }
    }

    /// The JSON object at `folder/Contents.json`.
    private static func contents(of folder: String) -> [String: Any]? {
        let path = (folder as NSString).appendingPathComponent("Contents.json")
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Whether a set's entry is for a dark appearance — Xcode writes
    /// `"appearances": [{"appearance": "luminosity", "value": "dark"}]` — and
    /// whether it is for one TUIkit never shows (high contrast, an idiom
    /// other than the Mac's or the universal one).
    private static func appearance(of entry: [String: Any]) -> (isDark: Bool, applies: Bool) {
        var isDark = false
        var applies = true
        for item in entry["appearances"] as? [[String: Any]] ?? [] {
            switch (item["appearance"] as? String, item["value"] as? String) {
            case ("luminosity", "dark"): isDark = true
            case ("luminosity", _): break
            default: applies = false  // contrast: high, and anything newer
            }
        }
        if let idiom = entry["idiom"] as? String, idiom != "universal", idiom != "mac" { applies = false }
        return (isDark, applies)
    }

    // MARK: - Colour sets

    private static func parseColorSet(at folder: String) -> ColorSet? {
        guard let colors = contents(of: folder)?["colors"] as? [[String: Any]] else { return nil }
        var any: Color?
        var dark: Color?
        for entry in colors {
            let (isDark, applies) = appearance(of: entry)
            guard applies, let spec = entry["color"] as? [String: Any], let color = color(from: spec) else { continue }
            if isDark {
                dark = dark ?? color
            } else {
                any = any ?? color
            }
        }
        guard let chosen = any ?? dark else { return nil }
        return ColorSet(any: chosen, dark: dark)
    }

    /// A colour as a colour set writes it: components in a colour space, as
    /// floating point (`"0.800"`), 8-bit (`"204"`) or hexadecimal (`"0xCC"`)
    /// text; or a reference to a system colour.
    ///
    /// Each component's text says how it is read, as `actool` reads it
    /// (measured, Xcode 26): digits alone are 8-bit whatever their size, so
    /// `"1"` is 1/255 and not 1.0, and that holds for the alpha too (Xcode
    /// writes alpha with a point, `"1.000"`); text with a point is floating
    /// point, even beside 8-bit components; and a JSON number, which Xcode
    /// never writes, is taken as it is.
    static func color(from spec: [String: Any]) -> Color? {
        if let reference = spec["reference"] as? String {
            return systemColor(named: reference)
        }
        guard let components = spec["components"] as? [String: Any] else { return nil }
        func value(_ key: String) -> Double? {
            guard let raw = components[key] else { return nil }
            if let number = raw as? Double { return number }
            guard let text = (raw as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
            let lowered = text.lowercased()
            if lowered.hasPrefix("0x"), let hex = Int(lowered.dropFirst(2), radix: 16) {
                return Double(hex) / 255
            }
            if !text.isEmpty, text.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
                let eightBit = Int(text)
            {
                return Double(eightBit) / 255
            }
            return Double(text)
        }
        let opacity = value("alpha") ?? 1
        let space = (spec["color-space"] as? String) ?? "srgb"
        if let white = value("white") {
            return Color(white: white, opacity: opacity)
        }
        guard let red = value("red"), let green = value("green"), let blue = value("blue") else { return nil }
        switch space {
        case "display-p3":
            return Color(.displayP3, red: red, green: green, blue: blue, opacity: opacity)
        case "extended-linear-srgb", "linear-srgb":
            return Color(.sRGBLinear, red: red, green: green, blue: blue, opacity: opacity)
        default:  // srgb, extended-srgb, and the device spaces Xcode also offers
            return Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
        }
    }

    /// The system colours a colour set may refer to, as TUIkit spells them;
    /// a reference missing here is one TUIkit has no counterpart for.
    private static func systemColor(named reference: String) -> Color? {  // swiftlint:disable:this cyclomatic_complexity
        // A switch rather than a `[String: Color]` literal, which a release build
        // assembled element by element: 34 ms of SIL optimisation against the
        // switch's 15 (2026-10-07). Read once a reference, while a catalogue is
        // parsed. Its complexity is its length: one case per name.
        switch reference {
        case "systemRedColor": .red
        case "systemOrangeColor": .orange
        case "systemYellowColor": .yellow
        case "systemGreenColor": .green
        case "systemMintColor": .mint
        case "systemTealColor": .teal
        case "systemCyanColor": .cyan
        case "systemBlueColor": .blue
        case "systemIndigoColor": .indigo
        case "systemPurpleColor": .purple
        case "systemPinkColor": .pink
        case "systemBrownColor": .brown
        case "systemGrayColor": .gray
        case "labelColor": .primary
        case "textColor": .primary
        case "secondaryLabelColor": .secondary
        case "controlAccentColor": .accentColor
        case "blackColor": .black
        case "whiteColor": .white
        case "clearColor": .clear
        default: nil
        }
    }

    // MARK: - Image sets

    private static func parseImageSet(at folder: String) -> ImageSet? {
        guard let images = contents(of: folder)?["images"] as? [[String: Any]] else { return nil }
        var any: ImageFile?
        var dark: ImageFile?
        for entry in images {
            let (isDark, applies) = appearance(of: entry)
            guard applies, let filename = entry["filename"] as? String,
                Image.resourceExtensions.contains((filename as NSString).pathExtension.lowercased())
            else { continue }
            let scaleText = (entry["scale"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "x")) ?? "1"
            let file = ImageFile(
                path: (folder as NSString).appendingPathComponent(filename), scale: Double(scaleText) ?? 1)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            if isDark {
                if file.scale > dark?.scale ?? 0 { dark = file }
            } else if file.scale > any?.scale ?? 0 {
                any = file
            }
        }
        guard any != nil || dark != nil else { return nil }
        return ImageSet(any: any, dark: dark)
    }
}
