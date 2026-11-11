//  🖥️ TUI — A Terminal UI framework for Swift
//  AllProgramsSettingsFile.swift
//
//  The person's settings for every TUI program, in `defaults.json`: one JSON
//  object made to be edited by hand, read entry by entry and written key by
//  key, keeping whatever TUI does not know.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation

/// The person's settings for every TUI program, kept in one file
/// (``AllProgramsSettingsLocation``): a JSON object whose keys are the
/// settings' (``UserSetting/key``), each a check's `true` or `false` or a
/// display option's identifier.
///
/// - An entry TUI can't use — a key it does not know, a value of the wrong
///   type, a palette it does not have — is skipped on its own, never the file.
/// - A write changes only the key it is for, over what is on disk at that
///   moment, so two programs writing at once each keep the other's change,
///   and every key TUI does not know is kept as it was.
/// - A file that is not a JSON object is not read, and never written over: a
///   mistake made by hand must not be lost to the next change made in a
///   panel. Reported through `StorageDiagnostics`.
package struct AllProgramsSettingsFile: Sendable {
    /// The file.
    package let url: URL

    package init(url: URL) {
        self.url = url
    }

    /// The person's file for this process (``AllProgramsSettingsLocation/file()``).
    package static func current() -> Self {
        Self(url: AllProgramsSettingsLocation.file())
    }

    /// What the file sets: every entry TUI can use. Empty where there is no
    /// file, or it is not a JSON object.
    package func read() -> SettingsLayer {
        guard let object = onDisk() else { return SettingsLayer() }
        var layer = SettingsLayer()
        for (key, json) in object ?? [:] {
            guard let setting = UserSetting(key: key), let value = json.settingValue, setting.accepts(value)
            else { continue }
            layer[setting] = value
        }
        return layer
    }

    /// Sets `setting` to `value` in the file, or takes it out where `value`
    /// is `nil`, keeping every other key as it is on disk now.
    ///
    /// - Returns: Whether the file was written: not where it is there and is
    ///   not a JSON object, nor where the write failed (both reported).
    @discardableResult
    package func write(_ value: SettingValue?, for setting: UserSetting) -> Bool {
        guard let existing = onDisk() else { return false }
        var object = existing ?? [:]
        object[setting.key] = value.map(JSONValue.init)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(object).writeAtomicallyWherePossible(to: url)
            return true
        } catch {
            StorageDiagnostics.report(
                StorageFailure(operation: .save, key: setting.key, path: url.path, underlying: error))
            return false
        }
    }

    /// The file's object: `.some(nil)` where there is no file, and `nil` where
    /// it is there but cannot be read as a JSON object (reported).
    private func onDisk() -> [String: JSONValue]?? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { return .some(nil) }
            StorageDiagnostics.report(StorageFailure(operation: .load, path: url.path, underlying: error))
            return nil
        }
        do {
            return .some(try JSONDecoder().decode([String: JSONValue].self, from: data))
        } catch {
            StorageDiagnostics.report(StorageFailure(operation: .load, path: url.path, underlying: error))
            return nil
        }
    }
}

// MARK: - Any JSON Value

/// Any JSON value, so a key TUI does not know is written back as it was read.
/// A number is kept as a `Double`, which writes an integer back as one.
private indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Self])
    case object([String: Self])

    init(_ value: SettingValue) {
        switch value {
        case .bool(let isOn): self = .bool(isOn)
        case .identifier(let id): self = .string(id)
        }
    }

    /// The setting value this is, where it is one a setting could take: a
    /// `true` or `false`, or a string.
    var settingValue: SettingValue? {
        switch self {
        case .bool(let isOn): .bool(isOn)
        case .string(let id): .identifier(id)
        default: nil
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // A `Bool` first: a number never decodes as one, so `1` stays a
        // number, which no check accepts.
        if container.decodeNil() {
            self = .null
        } else if let isOn = try? container.decode(Bool.self) {
            self = .bool(isOn)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([Self].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: Self].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let isOn): try container.encode(isOn)
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}
