//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ResolvedStrings.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The strings ``LocalizationService`` has resolved for a key, kept so the
/// next `Text` with that key is one lookup.
///
/// Two generations of ``limit`` answers each (``GenerationalMemo``): an app
/// that makes keys from data does not grow this for ever, and a working set
/// just over the limit is not read afresh every frame.
struct ResolvedStrings {
    /// What a lookup was asked: the key, its SwiftUI spelling, and the table.
    struct Key: Hashable {
        let key: String
        let swiftUIKey: String?
        let tableName: String?
        /// The bundle, by identity: a `Bundle` is one object per bundle, kept
        /// for the life of the process.
        let bundle: ObjectIdentifier?
        /// The language read first, where it is not the service's own: a
        /// subtree's `\.locale` naming another. `nil` for the service's.
        let language: String?

        init(key: String, swiftUIKey: String?, tableName: String?, bundle: Bundle?, language: String? = nil) {
            self.key = key
            self.swiftUIKey = swiftUIKey
            self.tableName = tableName
            self.bundle = bundle.map(ObjectIdentifier.init)
            self.language = language
        }
    }

    /// How many answers one generation holds.
    static let limit = 4_096

    private var memo = GenerationalMemo<Key, String>(limit: Self.limit)

    /// The answer kept for `key`, or `nil` where none is.
    func answer(for key: Key) -> String? {
        memo.answer(for: key)
    }

    /// Keeps `answer` for `key`, starting a new generation first if the
    /// current one is full.
    mutating func remember(_ answer: String, for key: Key) {
        memo.remember(answer, for: key)
    }
}
