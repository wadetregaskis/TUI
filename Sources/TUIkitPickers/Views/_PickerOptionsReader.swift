//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _PickerOptionsReader.swift
//
//  A picker's options, found where SwiftUI finds them: read from its content's
//  members in the context it is drawn in, not from the content's type.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// Resolves a picker's options from its content in the context it is drawn in,
/// and measures and draws what `build` makes of them.
///
/// The options are the content's members, as ``Group/init(subviews:transform:)``
/// resolves them (`subviewGroups(of:in:)`): so an option is found inside a
/// view of the app's own, a `Group`, an `AnyView` or an `if`, and its tag
/// behind any modifier written after `.tag(_:)` — the reading SwiftUI's
/// pickers have, where TUIkit's used to ask the content's type and found
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
struct _PickerOptionsReader<SelectionValue: Hashable, Content: View, Built: View>: View, Renderable, Layoutable {
    let content: Content
    let build: ([_PickerEntry<SelectionValue>]) -> Built

    var body: Never { fatalError("_PickerOptionsReader renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(build(entries(in: context)), proposal: proposal, context: builtScope(context))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(build(entries(in: context)), context: builtScope(context))
    }

    private func builtScope(_ context: RenderContext) -> RenderContext {
        context.withChildIdentity(type: Built.self, index: 1)
    }

    /// The options of `content`, each whose tag answers for `SelectionValue`,
    /// with a rule between groups; edge and doubled rules collapsed, so a
    /// group a condition empties leaves none behind.
    func entries(in context: RenderContext) -> [_PickerEntry<SelectionValue>] {
        let groups = subviewGroups(of: content, in: context.withChildIdentity(type: Content.self, index: 0))
        var entries: [_PickerEntry<SelectionValue>] = []
        for group in groups {
            if !group.header.isEmpty { entries.append(.divider) }
            for member in group.members {
                if member.isDivider {
                    entries.append(.divider)
                } else if let tag = member.containerValues.tag(for: SelectionValue.self) {
                    entries.append(.option(tag: tag, label: AnyView(member)))
                }
            }
            if !group.header.isEmpty { entries.append(.divider) }
        }
        return DropdownMenu.normalizedEntries(entries) { entry in
            if case .divider = entry { return true }
            return false
        }
    }
}
