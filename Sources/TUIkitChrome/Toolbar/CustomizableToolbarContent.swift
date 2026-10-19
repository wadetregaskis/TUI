//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomizableToolbarContent.swift
//
//  Toolbar content the person may customize: the protocol, the behaviours and
//  options an item is customized with, and the modifiers that state them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Protocol

/// Conforming types represent items that can be placed in various locations in
/// a customizable toolbar — mirrors SwiftUI's `CustomizableToolbarContent`.
///
/// Write it in a `toolbar(id:content:)`: ``ToolbarItem``s made with an `id:`,
/// ``ToolbarSpacer``s, a ``ToolbarTitleMenu``, composed with `if` and
/// `if`/`else`. The person customizes the items with an identifier — puts
/// them in the bar or takes them out, and moves them — from the bar's context
/// menu or the menu bar's View ▸ Customize Toolbar…; see
/// `toolbar(id:content:)`.
@MainActor
@preconcurrency
public protocol CustomizableToolbarContent: ToolbarContent where Body: CustomizableToolbarContent {}

/// `Never` is customizable toolbar content so the framework's own items can
/// declare `Body == Never`, as SwiftUI's do.
extension Never: CustomizableToolbarContent {}

extension ToolbarItem: CustomizableToolbarContent where ID == String {}

extension ToolbarSpacer: CustomizableToolbarContent {}

extension ToolbarTitleMenu: CustomizableToolbarContent {}

extension Optional: CustomizableToolbarContent where Wrapped: CustomizableToolbarContent {}

extension _ConditionalContent: CustomizableToolbarContent
where TrueContent: CustomizableToolbarContent, FalseContent: CustomizableToolbarContent {}

extension _TupleToolbarContent: CustomizableToolbarContent {}

extension _AnyToolbarContent: CustomizableToolbarContent {}

// MARK: - Behaviours and Options

/// The customization behavior of customizable toolbar content — mirrors
/// SwiftUI's `ToolbarCustomizationBehavior`.
public struct ToolbarCustomizationBehavior: Sendable, Equatable {
    /// What the person may do with the item.
    enum Kind: Sendable, Equatable {
        case `default`, reorderable, disabled
    }

    let kind: Kind

    /// The default customization behavior: the person may add the item to
    /// the toolbar, remove it, and move it within the toolbar.
    public static var `default`: Self { Self(kind: .default) }

    /// The reorderable customization behavior: the person may move the item
    /// within the toolbar, and may not remove it.
    public static var reorderable: Self { Self(kind: .reorderable) }

    /// The disabled customization behavior: the person may neither move the
    /// item nor remove it.
    public static var disabled: Self { Self(kind: .disabled) }
}

/// Options that influence the default customization behavior of customizable
/// toolbar content — mirrors SwiftUI's `ToolbarCustomizationOptions`.
public struct ToolbarCustomizationOptions: OptionSet, Sendable {
    /// The raw value.
    public let rawValue: Int

    /// Creates a new set from a raw value.
    ///
    /// - Parameter rawValue: The raw value with which to create the toolbar
    ///   customization options.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The person can always use the item, even if it's removed from the
    /// customizable toolbar: it stays in the toolbar's overflow menu, the
    /// `»` at the trailing end of its bar.
    public static let alwaysAvailable = Self(rawValue: 1 << 0)
}

/// What a customizable toolbar's modifiers said of one item.
struct _ToolbarItemCustomization {
    /// What the person may do with it.
    var behavior = ToolbarCustomizationBehavior.default
    /// Whether it starts out of the bar, for the person to add.
    var startsHidden = false
    /// Whether it stays in the overflow menu when the person removes it.
    var isAlwaysAvailable = false
    /// Whether the app hid it: out of the bar, and listed in the panel.
    var isHiddenByApp = false
}

// MARK: - The Modifiers

extension CustomizableToolbarContent {
    /// Configures the customization behavior of customizable toolbar content —
    /// mirrors SwiftUI's `CustomizableToolbarContent.customizationBehavior(_:)`.
    ///
    /// - Parameter behavior: The customization behavior of the customizable
    ///   toolbar content.
    /// - Returns: The content, customized as `behavior` says.
    public func customizationBehavior(_ behavior: ToolbarCustomizationBehavior) -> some CustomizableToolbarContent {
        _AnnotatedToolbarContent(content: self) { $0.customization.behavior = behavior }
    }

    /// Configures the way customizable toolbar items with the default
    /// behavior behave — mirrors SwiftUI's
    /// `CustomizableToolbarContent.defaultCustomization(_:options:)`.
    ///
    /// ``Visibility/hidden`` starts the items out of the toolbar, for the
    /// person to add from the customization panel;
    /// ``ToolbarCustomizationOptions/alwaysAvailable`` keeps an item the
    /// person removes in the toolbar's overflow menu.
    ///
    /// - Parameters:
    ///   - defaultVisibility: The default visibility of toolbar content with
    ///     the default customization behavior.
    ///   - options: The customization options to configure the behavior of
    ///     toolbar content with the default customization behavior.
    /// - Returns: The content, customized as stated.
    public func defaultCustomization(
        _ defaultVisibility: Visibility = .automatic, options: ToolbarCustomizationOptions = []
    ) -> some CustomizableToolbarContent {
        _AnnotatedToolbarContent(content: self) { item in
            if defaultVisibility == .hidden { item.customization.startsHidden = true }
            if options.contains(.alwaysAvailable) { item.customization.isAlwaysAvailable = true }
        }
    }

    /// Hides a toolbar item within its toolbar — mirrors SwiftUI's
    /// `CustomizableToolbarContent.hidden(_:)`.
    ///
    /// A hidden item is out of the bar, whatever the person chose, and is
    /// still listed in the customization panel, where the person can place
    /// it for when the app shows it again.
    ///
    /// - Parameter hidden: Whether the toolbar item is hidden.
    /// - Returns: The content, hidden if `hidden` is `true`.
    public func hidden(_ hidden: Bool = true) -> some CustomizableToolbarContent {
        _AnnotatedToolbarContent(content: self) { if hidden { $0.customization.isHiddenByApp = true } }
    }

    /// Controls the visibility of the background items share with the other
    /// items of their group — mirrors SwiftUI's
    /// `CustomizableToolbarContent.sharedBackgroundVisibility(_:)`; see
    /// ``ToolbarContent/sharedBackgroundVisibility(_:)``, which a terminal bar
    /// honours as it stands.
    ///
    /// - Parameter visibility: The visibility of the shared background.
    /// - Returns: The content, unchanged in a terminal bar.
    public func sharedBackgroundVisibility(_ visibility: Visibility) -> some CustomizableToolbarContent {
        _AnnotatedToolbarContent(content: self) { _ in }
    }
}

/// Customizable toolbar content whose items a modifier annotates as they are
/// handed over.
struct _AnnotatedToolbarContent<Content: CustomizableToolbarContent>: CustomizableToolbarContent,
    _ToolbarContentPrimitive
{
    let content: Content
    let annotate: (inout _ToolbarItemSpec) -> Void

    var body: Never { fatalError("_AnnotatedToolbarContent hands its items over itself") }

    func appendToolbarItems(to items: inout _ToolbarItemCollector) {
        let start = items.items.count
        TUIkitChrome.appendToolbarItems(content, to: &items)
        items.annotate(from: start, annotate)
    }
}
