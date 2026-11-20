//  A stand-in for TUIFoundation's paragraph attributes, in each shape the
//  attralign question weighed (2026-11-19). Built as module `StandIn`.
//
//  -D SAME_NAMED: what a6fa64c8f shipped. TUI declares Core Text's names
//                 itself on every platform.
//  (default):     the owner's ruling (a) plus its fallback. Core Text's own
//                 types where the SDK declares them (the macOS 26 SDK, told by
//                 FoundationModels, as AttributedTextSelection's arms are),
//                 TUI's identical ones where it does not (the macOS 15 SDK,
//                 Linux, Windows, WebAssembly); and everywhere a TUI-named
//                 attribute, `paragraphAlignment`, valued TUI's TextAlignment.

public import Foundation

#if !SAME_NAMED && canImport(Darwin) && canImport(FoundationModels)
    public import CoreText
    #if !NO_CORETEXT_REEXPORT
        @_exported import CoreText
    #endif
#endif

/// TUI's `TextAlignment` (`multilineTextAlignment`'s), as TUIFoundation has it.
public enum TextAlignment: Sendable, Hashable, CaseIterable {
    case leading, center, trailing
}

extension AttributeScopes {
    public struct SwiftUIAttributes: AttributeScope {
        #if SAME_NAMED || !(canImport(Darwin) && canImport(FoundationModels))
            public let alignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
        #endif
        public let paragraphAlignment: ParagraphAlignmentAttribute
        public let foundation: FoundationAttributes
    }
}

#if !SAME_NAMED && canImport(Darwin) && canImport(FoundationModels)
    extension AttributeScopes.SwiftUIAttributes {
        // A stored property cannot be `@available` newer than its type.
        @available(macOS 26, *)
        public var alignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute { fatalError() }
    }
#else
    extension AttributeScopes {
        public struct CoreTextAttributes {}
    }
    extension AttributeScopes.CoreTextAttributes {
        @frozen public enum TextAlignmentAttribute: CodableAttributedStringKey {
            public typealias Value = AttributedString.TextAlignment
            public static let name = "TUI.TextAlignment"
            public static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
        }
    }
    extension AttributedString {
        public enum TextAlignment: CaseIterable, Codable, Hashable, Sendable {
            case left, center, right
        }
    }
#endif

extension AttributeScopes.SwiftUIAttributes {
    @frozen public enum ParagraphAlignmentAttribute: AttributedStringKey {
        public typealias Value = TextAlignment
        public static let name = "TUI.ParagraphAlignment"
        public static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
    }
}

extension AttributeDynamicLookup {
    #if !SAME_NAMED && canImport(Darwin) && canImport(FoundationModels)
        @available(macOS 26, *)
        public subscript(
            dynamicMember keyPath: KeyPath<
                AttributeScopes.SwiftUIAttributes, AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
            >
        ) -> AttributeScopes.CoreTextAttributes.TextAlignmentAttribute {
            self[AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self]
        }
    #else
        public subscript(
            dynamicMember keyPath: KeyPath<
                AttributeScopes.SwiftUIAttributes, AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
            >
        ) -> AttributeScopes.CoreTextAttributes.TextAlignmentAttribute {
            self[AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self]
        }
    #endif

    public subscript(
        dynamicMember keyPath: KeyPath<
            AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.ParagraphAlignmentAttribute
        >
    ) -> AttributeScopes.SwiftUIAttributes.ParagraphAlignmentAttribute {
        self[AttributeScopes.SwiftUIAttributes.ParagraphAlignmentAttribute.self]
    }
}

/// What TUI reads: SwiftUI's `alignment` where the platform has it, then
/// TUI's `paragraphAlignment`.
public func drawnAlignment(of run: AttributedString.Runs.Run) -> TextAlignment? {
    #if !SAME_NAMED && canImport(Darwin) && canImport(FoundationModels)
        if #available(macOS 26, *), let alignment = run.alignment {
            switch alignment {
            case .left: return .leading
            case .center: return .center
            case .right: return .trailing
            @unknown default: return nil
            }
        }
    #else
        if let alignment = run.alignment {
            switch alignment {
            case .left: return .leading
            case .center: return .center
            case .right: return .trailing
            }
        }
    #endif
    return run.paragraphAlignment
}
