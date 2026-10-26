# List SwiftUI API Parity

## Preface

TUI's List component gains SwiftUI API parity with Section grouping, badges, list styles, selection control, and alternating row backgrounds. Section enables hierarchical organization with headers and footers. The `.badge()` modifier displays counts or labels right-aligned in rows. ListStyle provides visual variants like `.plain` and `.insetGrouped`. Per-item selection can be disabled via `.selectionDisabled()`. The `.listRowSeparator()` modifier is implemented as a stub with a warning since separators are not visually supported in TUI.

## Completed

**Date:** 2026-02-08

All phases implemented:
- Phase 1: Section with header/content/footer
- Phase 2: Badge Modifier (Int, String, Text overloads)
- Phase 3: ListStyle (PlainListStyle, InsetGroupedListStyle)
- Phase 4: Selection Disabled modifier
- Phase 5: Alternating Row Backgrounds (integrated into ListStyle)
- Phase 6: List Row Separator stub with warning

---

## Checklist

- [x] **Phase 1: Section**
  - [x] Create `Section` struct
  - [x] Implement SwiftUI-conformant initializers
  - [x] Add `SectionRowExtractor` protocol
  - [x] Update `_ListCore` for section rendering
  - [x] Write tests (14 tests)

- [x] **Phase 2: Badge Modifier**
  - [x] Create `BadgeKey` environment key
  - [x] Implement `.badge()` overloads
  - [x] Update row rendering for badges
  - [x] Write tests (20+ tests)

- [x] **Phase 3: ListStyle**
  - [x] Create `ListStyle` protocol
  - [x] Implement PlainListStyle, InsetGroupedListStyle
  - [x] Add environment key and modifier
  - [x] Update `_ListCore` to apply styles
  - [x] Write tests

- [x] **Phase 4: Selection Disabled**
  - [x] Create `SelectionDisabledKey` environment key
  - [x] Implement `.selectionDisabled()` modifier
  - [x] Write tests (5 tests)

- [x] **Phase 5: Alternating Row Backgrounds**
  - [x] Integrated into ListStyle.alternatingRowColors
  - [x] InsetGroupedListStyle enables by default
  - [x] PlainListStyle disables by default

- [x] **Phase 6: List Row Separator Stub**
  - [x] Create `ListRowSeparatorModifier`
  - [x] Implement `.listRowSeparator()` with warning
  - [x] Create Visibility and VerticalEdge.Set types
  - [x] Write tests (6 tests)

## Files

| File | Type |
|------|------|
| `Sources/TUI/Views/Section.swift` | Created |
| `Sources/TUI/Views/List.swift` | Modified |
| `Sources/TUI/Styles/ListStyle.swift` | Created |
| `Sources/TUI/Modifiers/BadgeModifier.swift` | Created |
| `Sources/TUI/Modifiers/SelectionDisabledModifier.swift` | Created |
| `Sources/TUI/Modifiers/ListRowSeparatorModifier.swift` | Created |
| `Sources/TUI/Extensions/View+Badge.swift` | Created |
| `Sources/TUI/Extensions/View+SelectionDisabled.swift` | Created |
| `Sources/TUI/Extensions/View+ListRowSeparator.swift` | Created |
| `Sources/TUI/Environment/Environment.swift` | Modified |
| `Tests/TUITests/SectionTests.swift` | Created |
| `Tests/TUITests/SectionListIntegrationTests.swift` | Created |
| `Tests/TUITests/ListStyleTests.swift` | Created |
| `Tests/TUITests/BadgeModifierTests.swift` | Created |
| `Tests/TUITests/SelectionDisabledTests.swift` | Created |
| `Tests/TUITests/ListRowSeparatorTests.swift` | Created |
