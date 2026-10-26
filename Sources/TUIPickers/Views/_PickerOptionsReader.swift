//  🖥️ TUI — A Terminal UI framework for Swift
//  _PickerOptionsReader.swift
//
//  A picker's options, found where SwiftUI finds them: read from its content's
//  members in the context it is drawn in, not from the content's type.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// Resolves a picker's options from its content in the context it is drawn in,
/// and measures and draws what `build` makes of them.
///
/// The options are the content's members, as ``Group/init(subviews:transform:)``
/// resolves them (`subviewGroups(of:in:)`): so an option is found inside a
/// view of the app's own, a `Group`, an `AnyView` or an `if`, and its tag
/// behind any modifier written after `.tag(_:)` — the reading SwiftUI's
/// pickers have, where TUI's used to ask the content's type and found
/// options only in seven of its own (deviation V7, fixed by the owner's ruling
/// of 2026-10-13). A `ForEach` row with no tag of its own is tagged with its
/// element's `id`, as SwiftUI's is. Each top-level `Section` is a group of
/// options, set apart from the rest by a rule, and a `Divider` among the
/// options is one.
///
/// Two scopes, one per side, as `Group(subviews:)` keeps them: the options
/// resolve one identity step in (`Content`, 0) and are pinned there, and what
/// `build` makes of them draws under (`Built`, 1), so an option's label and
/// the control's own views never share an identity or a `@State` box.
///
/// `build` is told, beside the options, whether the picker is drawn in a
/// pop-up menu's column (``EnvironmentValues/isInPopUpMenu``), where it is a
/// submenu or its options inline rather than a control: a body cannot see
/// that, the context can.
struct _PickerOptionsReader<SelectionValue: Hashable, Content: View, Built: View>: View, Renderable, Layoutable {
    let content: Content
    let build: (_ entries: [_PickerEntry<SelectionValue>], _ inPopUpMenu: Bool) -> Built

    var body: Never { fatalError("_PickerOptionsReader renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(
            build(entries(in: context), context.environment.isInPopUpMenu), proposal: proposal,
            context: builtScope(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(
            build(entries(in: context), context.environment.isInPopUpMenu), context: builtScope(context))
    }

    private func builtScope(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(type: Built.self, index: 1)
    }

    /// The options of `content`, each whose tag answers for `SelectionValue`,
    /// with a rule between groups and a section's header as the title of its
    /// group, under the rule; edge and doubled rules collapsed, so a group a
    /// condition empties leaves no rule of its own behind. A section's header
    /// stays when a condition empties the section: a macOS menu picker keeps
    /// it, between its separators over no options, and sizes the collapsed
    /// control to it (`Tools/SwiftUIProbes/Picker sections/pickersection.out`,
    /// `emptied`), as the title counts here.
    func entries(in context: RenderContext) -> [_PickerEntry<SelectionValue>] {
        let groups = subviewGroups(of: content, in: context.withChildIdentity(type: Content.self, index: 0))
        var entries: [_PickerEntry<SelectionValue>] = []
        for group in groups {
            // A section is set apart by rules with a header or without one,
            // as a macOS menu picker sets it apart (`Tools/SwiftUIProbes/Picker
            // sections/pickersection.out`); its header is its title, under the
            // first rule.
            if group.isSection {
                entries.append(.divider)
                if let title = Self.title(of: group.header) { entries.append(.title(title)) }
            }
            for member in group.members {
                if member.isDivider {
                    entries.append(.divider)
                } else if let tag = member.containerValues.tag(for: SelectionValue.self) {
                    entries.append(.option(tag: tag, label: AnyView(member)))
                } else {
                    // SwiftUI shows every member as an item, tagged or not
                    // (measured); a picker that can only select by tag leaves
                    // it out, and says so (owner ruling RC5).
                    DroppedMember.report(
                        member.memberView, leftOutBy: "Picker",
                        because:
                            "it has no tag of the selection's type, \(SelectionValue.self). Tag it with .tag(_:), as a value of that type.")
                }
            }
            if group.isSection { entries.append(.divider) }
        }
        return DropdownMenu.normalizedEntries(entries) { entry in
            if case .divider = entry { return true }
            return false
        }
    }

    /// A section header's members as one title view: the member itself where
    /// there is one, side by side where there are several, `nil` where the
    /// section has no header.
    private static func title(of header: [Subview]) -> AnyView? {
        switch header.count {
        case 0: nil
        case 1: AnyView(header[0])
        default: AnyView(HStack(spacing: 1) { ForEach(header) { $0 } })
        }
    }
}
