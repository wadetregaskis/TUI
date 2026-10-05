//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AssetCatalog.swift
//
//  An asset catalogue as `swift build` leaves it: the `.xcassets` folder,
//  copied into the resource bundle uncompiled, read as the JSON it is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

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
/// resources. A name is found at its path inside one (`Brand`, or
/// `Colors/Brand` under a folder that provides a namespace) or, failing that,
/// as the last component of any set of that name deeper in.
///
/// What is read is kept, by catalogue and name, for the process: a body that
/// names a colour reads it on every frame.
enum AssetCatalog {
    /// A colour set's colours: the one for any appearance, and the one for a
    /// dark appearance where the set has one.
    struct ColorSet: Equatable {
        let any: Color
        let dark: Color?

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

    /// The `.colorset` / `.imageset` folder for `name`, first at its path in a
    /// catalogue, then by its last component anywhere in one.
    private static func folder(of kind: Kind, named name: String, in bundle: Bundle) -> String? {
        let manager = FileManager.default
        let setName = "\(name).\(kind.rawValue)"
        let lastComponent = "\((name as NSString).lastPathComponent).\(kind.rawValue)"
        for catalog in catalogs(in: bundle) {
            let direct = (catalog as NSString).appendingPathComponent(setName)
            if manager.fileExists(atPath: (direct as NSString).appendingPathComponent("Contents.json")) {
                return direct
            }
            guard let walk = manager.enumerator(atPath: catalog) else { continue }
            while let relative = walk.nextObject() as? String {
                if (relative as NSString).lastPathComponent == lastComponent {
                    return (catalog as NSString).appendingPathComponent(relative)
                }
            }
        }
        return nil
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
            guard let number = Double(text) else { return nil }
            // An 8-bit integer component is written without a point.
            return !text.contains(".") && number > 1 ? number / 255 : number
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
    private static func systemColor(named reference: String) -> Color? {
        systemColors[reference]
    }

    private static let systemColors: [String: Color] = [
        "systemRedColor": .red, "systemOrangeColor": .orange, "systemYellowColor": .yellow,
        "systemGreenColor": .green, "systemMintColor": .mint, "systemTealColor": .teal,
        "systemCyanColor": .cyan, "systemBlueColor": .blue, "systemIndigoColor": .indigo,
        "systemPurpleColor": .purple, "systemPinkColor": .pink, "systemBrownColor": .brown,
        "systemGrayColor": .gray, "labelColor": .primary, "textColor": .primary,
        "secondaryLabelColor": .secondary, "controlAccentColor": .accentColor,
        "blackColor": .black, "whiteColor": .white, "clearColor": .clear,
    ]

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
