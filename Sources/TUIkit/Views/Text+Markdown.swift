//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Text+Markdown.swift
//
//  The Markdown SwiftUI applies to a `Text` made from a key, as a `Text`'s
//  runs. The parse itself is `InlineMarkdown`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Text {
    /// The URL a Markdown link's destination names, or `nil` for none.
    ///
    /// `URL(string:)`, as Foundation's parse makes a link (measured: `<a b>`
    /// links to `a%20b`, and an empty destination is no link at all). Where
    /// that refuses a destination — swift-foundation is stricter about some
    /// characters than Darwin's — the destination is percent-encoded first, so
    /// the link survives on both.
    nonisolated static func linkURL(_ destination: String) -> URL? {
        guard !destination.isEmpty else { return nil }
        if let url = URL(string: destination) { return url }
        return destination.addingPercentEncoding(withAllowedCharacters: Self.linkCharacters)
            .flatMap(URL.init(string:))
    }

    /// Everything a URL may hold as written: the unreserved characters, the
    /// reserved ones (which are its syntax) and `%`.
    nonisolated private static let linkCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
}
