//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NavigationPath.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - NavigationPath

/// A type-erased list of data representing the content of a navigation stack.
/// Matches SwiftUI's type of the same name.
///
/// Use a `NavigationPath` when the screens a ``NavigationStack`` can push are
/// driven by values of *different* types — a `Recipe` here, an `Ingredient`
/// there. A homogeneous stack can bind a plain array instead:
/// `NavigationStack(path: $recipes)`.
///
/// ```swift
/// @State private var path = NavigationPath()
///
/// var body: some View {
///     NavigationStack(path: $path) {
///         List {
///             NavigationLink("Bread", value: Recipe.bread)
///         }
///         .navigationDestination(for: Recipe.self) { RecipeView(recipe: $0) }
///         .navigationDestination(for: Ingredient.self) { IngredientView($0) }
///     }
/// }
///
/// // Somewhere else — return to the root from any depth:
/// path.removeLast(path.count)
/// ```
///
/// A path whose every value is `Codable` can be saved and restored through
/// ``codable`` and ``init(_:)-(CodableRepresentation)`` — see
/// ``CodableRepresentation``.
public struct NavigationPath: Equatable {

    /// The pushed values, root-most first. `AnyHashable` is exactly the
    /// erasure SwiftUI describes: the elements need only be `Hashable`, and
    /// `AnyHashable` keeps both the value and its dynamic type — which is what
    /// lets ``NavigationStack`` find the matching `.navigationDestination`.
    var elements: [AnyHashable]

    /// Creates an empty navigation path.
    public init() {
        self.elements = []
    }

    /// Creates a navigation path from the given hashable values.
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    /// Creates a navigation path from already-erased values.
    init(erased elements: [AnyHashable]) {
        self.elements = elements
    }

    /// The number of values in the path.
    public var count: Int { elements.count }

    /// Whether the path is empty — the stack is showing its root view.
    public var isEmpty: Bool { elements.isEmpty }

    /// Appends a value to the end of the path, pushing a screen.
    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    /// Removes the last `k` values, popping that many screens.
    ///
    /// - Parameter k: How many values to remove. Defaults to 1. Removing more
    ///   than the path holds is a programmer error, as in SwiftUI.
    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }
}

// MARK: - Saving and restoring

extension NavigationPath {
    /// A serializable form of a navigation path, for saving the screens a
    /// stack has pushed and restoring them on the next launch.
    ///
    /// Each value is recorded with its type's name, which is how decoding
    /// knows what to rebuild — the same scheme SwiftUI uses. So a value's type
    /// must still exist, under the same name, in the process that decodes it;
    /// one that does not makes decoding throw rather than lose a screen. That
    /// rules out `private` and `fileprivate` types, whose names carry a
    /// per-file discriminator the runtime lookup cannot resolve. The encoded
    /// form is this type's own, not SwiftUI's.
    ///
    /// ```swift
    /// // Saving:
    /// if let codable = path.codable {
    ///     saved = try JSONEncoder().encode(codable)
    /// }
    /// // Restoring:
    /// let codable = try JSONDecoder().decode(
    ///     NavigationPath.CodableRepresentation.self, from: saved)
    /// path = NavigationPath(codable)
    /// ```
    public struct CodableRepresentation: Codable, Equatable {
        /// One value: its type's mangled name, the value as JSON, and the
        /// value itself. Equality is by the first two — the encoded form.
        fileprivate struct Entry: Equatable {
            let typeName: String
            let json: String
            let value: AnyHashable

            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.typeName == rhs.typeName && lhs.json == rhs.json
            }
        }

        /// Root-most first, as in the path.
        fileprivate let entries: [Entry]

        fileprivate init(entries: [Entry]) {
            self.entries = entries
        }

        /// Decodes a representation, resolving each value's type by name.
        ///
        /// - Throws: `DecodingError.dataCorrupted` if a type is not known to
        ///   this process (or is not `Decodable`), or a value does not decode.
        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var entries: [Entry] = []
            while !container.isAtEnd {
                let typeName = try container.decode(String.self)
                let json = try container.decode(String.self)
                guard let type = _typeByName(typeName) as? any (Decodable & Hashable).Type else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "No Decodable & Hashable type named \(typeName)")
                }
                let value = try Self.decode(type, from: Data(json.utf8))
                entries.append(Entry(typeName: typeName, json: json, value: value))
            }
            self.entries = entries
        }

        /// Encodes each value as its type's name followed by its JSON.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            for entry in entries {
                try container.encode(entry.typeName)
                try container.encode(entry.json)
            }
        }

        /// Decodes one value of a type known only at run time.
        private static func decode<T: Decodable & Hashable>(
            _ type: T.Type, from data: Data
        ) throws -> AnyHashable {
            AnyHashable(try JSONDecoder().decode(T.self, from: data))
        }
    }

    /// The path in a form that can be encoded, or `nil` if any value in it is
    /// not `Codable`.
    ///
    /// Whether a value is `Codable` is asked of the value itself, so it does
    /// not matter which `append` put it there — SwiftUI decides by the
    /// overload, and answers `nil` for a `Codable` value appended through
    /// generic code that only knew it was `Hashable`.
    public var codable: CodableRepresentation? {
        var entries: [CodableRepresentation.Entry] = []
        for element in elements {
            guard let value = element.base as? any Codable,
                  let typeName = _mangledTypeName(type(of: value)),
                  let data = try? JSONEncoder().encode(value),
                  let json = String(bytes: data, encoding: .utf8)
            else { return nil }
            entries.append(.init(typeName: typeName, json: json, value: element))
        }
        return CodableRepresentation(entries: entries)
    }

    /// Creates a navigation path from its saved representation.
    ///
    /// - Parameter codable: A representation from ``codable``, typically
    ///   decoded from storage.
    public init(_ codable: CodableRepresentation) {
        self.init(erased: codable.entries.map(\.value))
    }
}
