//  🖥️ TUI — A Terminal UI framework for Swift
//  TextCharacters.swift
//
//  A run of characters held as their UTF-8: what a TextEditor's line and a
//  vertical field's text are, in place of an array of `Character`s, which
//  costs 16 bytes a character (EDMEM-1).
//
//  Created by Wade Tregaskis
//  License: MIT

/// Characters, indexed from 0 as an array of them is, held as their UTF-8 in
/// one string, with where each starts kept only when some character is more
/// than one byte.
///
/// What a ``TextEditor``'s lines and a vertical field's text are made of. They
/// were `[Character]`, 16 bytes a character: 491 of the 680 bytes a line a 10
/// MB document cost its editor (EDMEM-1, 2026-11-22). Here a line of ASCII is
/// its bytes, in a string's own storage (none of its own for up to 15 of them),
/// and is indexed by them; any other line keeps a 4-byte start a character
/// beside its bytes.
///
/// It is the array it replaces, not the string it holds: the characters are
/// the ones it was made of, even where the string would join them — an "e"
/// and a combining acute appended one after the other stay two, as they did in
/// an array, until ``segmented()`` makes them the string's own. Every
/// character it hands back is one of those, never a part of one.
struct TextCharacters {
    /// The characters' UTF-8, in order: native and contiguous, so its count
    /// and its offsets are O(1).
    private(set) var storage: String

    /// Where each character starts in ``storage``, in bytes; `nil` where each
    /// is one byte, the character at an index then the byte there.
    private var starts: [UInt32]?

    /// No characters.
    init() {
        storage = ""
        starts = nil
    }

    /// `string`'s characters: the string's own, as it splits them.
    init(_ string: String) {
        var string = string
        string.makeContiguousUTF8()
        storage = string
        starts = Self.characterStarts(of: string)
    }

    /// `string`'s characters, as ``init(_:)-(String)`` takes them.
    init(_ string: Substring) {
        self.init(String(string))
    }

    /// Characters whose bytes are `storage`, each starting at the offset
    /// `starts` gives (`nil`: one a byte).
    private init(storage: String, starts: [UInt32]?) {
        self.storage = storage
        self.starts = starts
    }

    /// Where each of `string`'s characters starts, in bytes, or `nil` where
    /// each is one byte: an ASCII string with no CR before an LF, which are
    /// one character (GB3), found in one pass of its bytes.
    private static func characterStarts(of string: String) -> [UInt32]? {
        var afterCR = false
        var isOneByteEach = true
        for byte in string.utf8 {
            if byte >= 0x80 || (afterCR && byte == 0x0A) {
                isOneByteEach = false
                break
            }
            afterCR = byte == 0x0D
        }
        if isOneByteEach { return nil }
        var starts: [UInt32] = []
        var offset = 0
        for character in string {
            starts.append(UInt32(offset))
            offset += character.utf8.count
        }
        return starts
    }

    /// The string these characters spell: their bytes, at no cost.
    var string: String { storage }

    /// The UTF-8 offset at which the character at `index` starts; the bytes'
    /// count for `index == count`.
    func utf8Offset(of index: Int) -> Int {
        guard let starts else { return index }
        return index < starts.count ? Int(starts[index]) : storage.utf8.count
    }

    /// The characters as their bytes, where each is one ASCII byte (`nil`
    /// where one is not): read a byte at a time, without the string's index
    /// arithmetic, by a walk of every character (``SoftWrapLayout``).
    var asciiBytes: ASCIIBytes? {
        starts == nil ? ASCIIBytes(bytes: Array(storage.utf8)) : nil
    }

    /// Characters of one ASCII byte each, read from an array of the bytes.
    struct ASCIIBytes: RandomAccessCollection {
        typealias Indices = Range<Int>
        let bytes: [UInt8]
        var startIndex: Int { 0 }
        var endIndex: Int { bytes.count }
        subscript(position: Int) -> Character { TextCharacters.ascii[Int(bytes[position])] }
    }

    /// Whether every character is one printable ASCII byte, a space to a
    /// tilde: one cell each, told from the bytes alone (``TabLayout``'s fast
    /// path).
    var isPrintableASCII: Bool {
        starts == nil && storage.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
    }

    /// How many bytes the character at `index` is: its `utf8.count`, read
    /// from the offsets rather than the character made to ask it.
    func utf8Length(of index: Int) -> Int {
        guard let starts else { return 1 }
        let upper = index + 1 < starts.count ? Int(starts[index + 1]) : storage.utf8.count
        return upper - Int(starts[index])
    }

    /// The bytes of the characters in `range`.
    func utf8Offsets(of range: Range<Int>) -> Range<Int> {
        utf8Offset(of: range.lowerBound)..<utf8Offset(of: range.upperBound)
    }

    /// The string the characters in `range` spell.
    func string(in range: Range<Int>) -> String {
        if range.lowerBound == 0, range.upperBound == count { return storage }
        return String(storage[stringIndices(ofBytes: utf8Offsets(of: range))])
    }

    /// The characters in `range`, as characters of their own.
    func characters(in range: Range<Int>) -> Self {
        if range.lowerBound == 0, range.upperBound == count { return self }
        let bytes = utf8Offsets(of: range)
        let taken = String(storage[stringIndices(ofBytes: bytes)])
        guard let starts else { return Self(storage: taken, starts: nil) }
        let base = UInt32(bytes.lowerBound)
        return Self(storage: taken, starts: starts[range].map { $0 - base })
    }

    /// The characters as their string splits them: an "e" and a combining
    /// acute that were two, one. What a line an edit made is laid out as
    /// (``EditorLayout/segmented(_:)``).
    func segmented() -> Self {
        Self(storage)
    }

    /// Whether `other` is the same characters, byte for byte and split the
    /// same: not `==`, which takes canonically equivalent characters for one.
    func hasSameBytes(as other: Self) -> Bool {
        starts == other.starts && storage.utf8.elementsEqual(other.storage.utf8)
    }

    /// The `String.Index` range of `bytes` in ``storage``.
    private func stringIndices(ofBytes bytes: Range<Int>) -> Range<String.Index> {
        let utf8 = storage.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: bytes.lowerBound)
        return lower..<utf8.index(lower, offsetBy: bytes.count)
    }
}

// MARK: - Collection

extension TextCharacters: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    typealias Indices = Range<Int>

    var startIndex: Int { 0 }
    var endIndex: Int { starts?.count ?? storage.utf8.count }
    var count: Int { endIndex }
    var isEmpty: Bool { storage.isEmpty }

    subscript(position: Int) -> Character {
        get {
            let utf8 = storage.utf8
            guard let starts else {
                return Self.ascii[Int(utf8[utf8.index(utf8.startIndex, offsetBy: position)])]
            }
            let lower = Int(starts[position])
            let upper = position + 1 < starts.count ? Int(starts[position + 1]) : utf8.count
            return Character(String(storage[stringIndices(ofBytes: lower..<upper)]))
        }
        set {
            replaceSubrange(position..<(position + 1), with: CollectionOfOne(newValue))
        }
    }

    /// Each ASCII byte's character, made once: what an ASCII line's
    /// subscript hands back, where `Character(Unicode.Scalar(byte))` made a
    /// string for every character drawn (0.9% of `bigtext-find`'s time).
    /// 128 characters, not text: a table of glyphs, as a mnemonic's are.
    fileprivate static let ascii: [Character] = (0..<128).map { Character(Unicode.Scalar(UInt8($0))) }

    mutating func append(_ character: Character) {
        let length = character.utf8.count
        if starts == nil, length != 1 { starts = Array(0..<UInt32(storage.utf8.count)) }
        starts?.append(UInt32(storage.utf8.count))
        storage.append(contentsOf: String(character))
    }

    mutating func append<S: Sequence>(contentsOf newElements: S) where S.Element == Character {
        if let characters = newElements as? Self {
            replaceSubrange(endIndex..<endIndex, with: characters)
        } else if let slice = newElements as? Slice<Self> {
            replaceSubrange(endIndex..<endIndex, with: slice)
        } else {
            for character in newElements { append(character) }
        }
    }

    mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C)
    where C.Element == Character {
        let inserted = Self.characters(newElements)
        if subrange.isEmpty, subrange.lowerBound == count {
            appendInPlace(inserted)
            return
        }
        let bytes = utf8Offsets(of: subrange)
        let span = stringIndices(ofBytes: bytes)
        var joined = String()
        joined.reserveCapacity(storage.utf8.count - bytes.count + inserted.storage.utf8.count)
        joined.append(contentsOf: storage[..<span.lowerBound])
        joined.append(contentsOf: inserted.storage)
        joined.append(contentsOf: storage[span.upperBound...])
        if starts == nil, inserted.starts == nil {
            storage = joined
            return
        }
        // Each side's starts, one a byte where it keeps none.
        let shift = inserted.storage.utf8.count - bytes.count
        var merged: [UInt32] = []
        merged.reserveCapacity(count - subrange.count + inserted.count)
        for index in 0..<subrange.lowerBound { merged.append(UInt32(utf8Offset(of: index))) }
        for index in 0..<inserted.count { merged.append(UInt32(bytes.lowerBound + inserted.utf8Offset(of: index))) }
        for index in subrange.upperBound..<count { merged.append(UInt32(utf8Offset(of: index) + shift)) }
        storage = joined
        starts = merged.count == joined.utf8.count ? nil : merged
    }

    /// `inserted` after these characters, in this storage: amortised, as an
    /// array's append is, not the whole line copied for each, which made a
    /// line that Replace All grows a piece at a time
    /// (``EditedLines/apply(descending:)``) cost its length for every piece.
    private mutating func appendInPlace(_ inserted: Self) {
        let base = storage.utf8.count
        if starts != nil || inserted.starts != nil {
            if starts == nil { starts = Array(0..<UInt32(base)) }
            for index in 0..<inserted.count { starts?.append(UInt32(base + inserted.utf8Offset(of: index))) }
        }
        storage.append(contentsOf: inserted.storage)
    }

    /// `elements` as characters of their own: at once where they are some
    /// already, else their bytes appended a character at a time.
    private static func characters<C: Collection>(_ elements: C) -> Self where C.Element == Character {
        if let elements = elements as? Self { return elements }
        if let slice = elements as? Slice<Self> { return slice.base.characters(in: slice.startIndex..<slice.endIndex) }
        var made = Self()
        made.storage.reserveCapacity(elements.count)
        for character in elements { made.append(character) }
        return made
    }
}

// MARK: - Equality, literals, description

extension TextCharacters: Equatable {
    /// Whether the two are the same characters, as two arrays of them are
    /// equal: each `==` the other's at its index.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.hasSameBytes(as: rhs) || lhs.elementsEqual(rhs)
    }
}

extension TextCharacters: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Character...) {
        self.init(elements)
    }
}

extension TextCharacters: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { storage }
    var debugDescription: String { "TextCharacters(\(Array(self)))" }
}
