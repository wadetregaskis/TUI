//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerMenuRows.swift
//
//  A `Picker` written in a pop-up menu: its options as rows of a menu, the
//  selected one checked — in a submenu, or inline.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

/// A picker's options as rows of a menu: each a button that selects its
/// option, the selected one checked (✓) in a column every row keeps, a
/// `Divider` between groups and a section's header as a title over its
/// options — what a macOS menu draws a `Picker`'s options as, in a submenu or
/// inline (measured, `Tools/SwiftUIProbes/Menu items and alert buttons/pickers.out`).
///
/// No option is checked where the selection matches none, or where the picker
/// shows several sources that disagree (`Picker(sources:)`). A disabled picker
/// draws its options disabled, as macOS's does: its submenu still opens.
struct _PickerMenuRows<SelectionValue: Hashable>: View {
    let entries: [_PickerEntry<SelectionValue>]
    let selection: Binding<SelectionValue>
    let isMixed: Bool
    let isDisabled: Bool

    var body: some View {
        // A stack round the loop: a `ForEach` resolves only where a container
        // asks it for its children.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries.indices, id: \.self) { index in
                row(entries[index])
            }
        }
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func row(_ entry: _PickerEntry<SelectionValue>) -> some View {
        switch entry {
        case .option(let tag, let label):
            let selection = selection
            let isSelected = !isMixed && selection.wrappedValue == tag
            Button {
                selection.wrappedValue = tag
            } label: {
                HStack(spacing: 1) {
                    // Verbatim: a glyph, not display text.
                    Text(verbatim: isSelected ? DropdownMenu.selectedMarker : " ")
                    label
                }
            }
        case .divider:
            Divider()
        case .title(let title):
            _MenuSectionHeader(header: title)
        }
    }
}

/// A picker drawn inline in a menu: its label as the title of a section that
/// holds its options, between separators — what a macOS menu draws an
/// `.inline` picker as (measured, `pickers.out`).
struct _PickerInlineMenuSection<Label: View, SelectionValue: Hashable>: View {
    let label: Label
    let rows: _PickerMenuRows<SelectionValue>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            _MenuSectionHeader(header: label)
            rows
            Divider()
        }
    }
}
