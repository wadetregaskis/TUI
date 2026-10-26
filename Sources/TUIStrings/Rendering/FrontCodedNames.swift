//  🖥️ TUI — A Terminal UI framework for Swift
//  FrontCodedNames.swift
//
//  A sorted list of ASCII names baked into a binary as compile-time data,
//  front-coded in blocks, and searched without building a String: the shape
//  of the SF Symbols name table (`Documentation/Swift language/Baking a large
//  static lookup table in Swift.md`, "Front-coding the names"), and of every
//  generated table that keys by name.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A generated table's names: sorted ascending by their bytes, each ended by
/// a newline (the last one too), front-coded in blocks of ``blockSize`` — a
/// block's first name, its head, in full; every other name as one byte, how
/// many leading bytes it shares with the name before it, then the rest.
///
/// ```swift
/// static let nameBlocks: StaticString = """
/// 0.circle
/// \u{8}.ar
/// \u{9}fill
/// …
/// """
/// static let blockStarts: [UInt32] = [0, 91, 192, …]  // one per block, and the end
/// ```
///
/// A name's position in the list is its index into whatever the table keeps
/// beside the names.
struct FrontCodedNames {
    /// The names, as above.
    let blocks: StaticString

    /// The byte offset of each block in ``blocks``, and of the end: the
    /// number of blocks plus one.
    let blockStarts: [UInt32]

    /// Names per block; the last block holds the rest.
    let blockSize: Int

    /// How many names there are.
    let count: Int

    /// The byte that ends every name. Computed, not stored: a literal in every
    /// comparison of the search, with no global to read.
    private static var newline: UInt8 { UInt8(ascii: "\n") }

    /// The position of `name` among the names, or `nil`. Compares raw UTF-8
    /// bytes, which for ASCII names is Swift `String` ordering, so the search
    /// touches no `String` and, on the common path, allocates nothing.
    func index(of name: String) -> Int? {
        // Fast path: a native Swift string exposes contiguous UTF-8 storage.
        let found: Int?? = name.utf8.withContiguousStorageIfAvailable { index(of: $0) }
        // Rare fallback (a bridged NSString): copy the query bytes once.
        return found ?? index(copying: name.utf8)
    }

    /// ``index(of:)-(String)``'s fallback for a string without contiguous
    /// UTF-8 storage, searched in one copy of its bytes. Internal so a test
    /// reaches it directly: whether a given string bridges without contiguous
    /// UTF-8 is up to the OS's Swift runtime, not the test.
    func index(copying bytes: String.UTF8View) -> Int? {
        Array(bytes).withUnsafeBufferPointer { index(of: $0) }
    }

    /// The position of `query` among the names, or `nil`: a binary search of
    /// the block heads for the last one at or below the query, then a walk of
    /// that block.
    func index(of query: UnsafeBufferPointer<UInt8>) -> Int? {
        blocks.withUTF8Buffer { blob in
            var low = 0
            var high = blockStarts.count - 1  // the number of blocks
            while low < high {
                let mid = low + (high - low) / 2
                if Self.compareHead(blob, at: Int(blockStarts[mid]), to: query) <= 0 {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            // `low` is the first block whose head sorts above the query.
            guard low > 0 else { return nil }
            return walk(blob, block: low - 1, for: query)
        }
    }

    /// Calls `body` with each name's position and bytes, in order: one pass,
    /// each name rebuilt from the one before it. For a table that builds every
    /// entry once, on first use.
    func forEachName(_ body: (Int, [UInt8]) -> Void) {
        blocks.withUTF8Buffer { blob in
            var name: [UInt8] = []
            var position = 0
            for index in 0..<count {
                if index.isMultiple(of: blockSize) {
                    name.removeAll(keepingCapacity: true)
                } else {
                    name.removeLast(name.count - Int(blob[position]))
                    position += 1
                }
                while blob[position] != Self.newline {
                    name.append(blob[position])
                    position += 1
                }
                position += 1
                body(index, name)
            }
        }
    }

    /// Unsigned byte-lexicographic comparison of the head name starting at
    /// `start` against `query`: negative if the head sorts before the query,
    /// `0` if equal, positive after. Equals Swift `String` ordering because
    /// every name is ASCII.
    private static func compareHead(
        _ blob: UnsafeBufferPointer<UInt8>, at start: Int, to query: UnsafeBufferPointer<UInt8>
    ) -> Int {
        var position = start
        var offset = 0
        while true {
            let byte = blob[position]
            if byte == newline { return offset == query.count ? 0 : -1 }
            if offset == query.count { return 1 }
            let other = query[offset]
            if byte != other { return byte < other ? -1 : 1 }
            position += 1
            offset += 1
        }
    }

    /// The position of `query` in `block`, whose head sorts at or below it, or
    /// `nil`.
    ///
    /// Nothing is rebuilt. The walk keeps `matched`, how many leading bytes of
    /// the query the current name shares, while that name still sorts below
    /// the query. The next name shares `shared` bytes with the current one: if
    /// more than `matched`, it agrees with the current name where that name
    /// fell below the query, so it does too, with the same `matched`; if fewer,
    /// it rose above the current name at a byte the query matched, so it — and
    /// every name after it — sorts above the query; only a name sharing exactly
    /// `matched` has its suffix compared with the query.
    private func walk(
        _ blob: UnsafeBufferPointer<UInt8>, block: Int, for query: UnsafeBufferPointer<UInt8>
    ) -> Int? {
        var position = Int(blockStarts[block])
        let end = Int(blockStarts[block + 1])
        var index = block * blockSize
        var matched = 0
        var shared = 0  // the head is stored in full: it shares nothing
        while true {
            if shared < matched { return nil }
            if shared == matched {
                while blob[position] != Self.newline, matched < query.count, blob[position] == query[matched] {
                    position += 1
                    matched += 1
                }
                let byte = blob[position]
                if byte == Self.newline {
                    if matched == query.count { return index }
                    // A proper prefix of the query: below it, so walk on.
                } else if matched == query.count || byte > query[matched] {
                    return nil  // above the query
                }
            }
            while blob[position] != Self.newline { position += 1 }
            position += 1
            index += 1
            guard position < end else { return nil }
            shared = Int(blob[position])
            position += 1
        }
    }
}
