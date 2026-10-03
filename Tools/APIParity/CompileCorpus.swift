//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompileCorpus.swift
//
//  SwiftUI source, written the way SwiftUI's own documentation writes it, that
//  must COMPILE against TUIkit. It is never run — `swiftc -typecheck` is the
//  whole test (`Tools/APIParity/compile_corpus.sh`).
//
//  This is the half `api_parity.py` cannot see. That tool compares argument
//  labels, so it can tell you a name is absent; it cannot tell you whether the
//  call site a developer actually writes binds to anything. The two failure
//  directions it misses are opposite and both real:
//
//  * A symbol the tool reports as MISSING that in fact compiles, because
//    TUIkit's declaration adds optional parameters after SwiftUI's —
//    `alert(_:isPresented:actions:)` is spelled `…:borderStyle:borderColor:
//    titleColor:` here. `source_compatible` now models that, and this file is
//    what proves the model right rather than merely plausible.
//  * A symbol the tool reports as PRESENT that does not compile, because only
//    the labels match: a `@ViewBuilder` that is not one, a trailing closure in
//    a different position, a generic constraint the call cannot satisfy. The
//    `Alert.warning(…) { … }` defect was exactly this shape and the symbol
//    diff was blind to it.
//
//  Add a snippet whenever a signature's compilability is the interesting
//  question — not one per symbol; this is a corpus of the calls that could
//  plausibly break, not an inventory.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Extra optional arguments must not break SwiftUI's spelling

/// Each of these is reported by `api_parity.py` as source-compatible rather
/// than missing, because TUIkit's declaration appends defaulted parameters of
/// its own. If a default is ever removed, this stops compiling — which is the
/// point: the tool would go on calling it compatible.
@MainActor
private struct AddedOptionalArguments: View {
    @State private var isPresented = false

    var body: some View {
        VStack {
            Text("body")
                // TUIkit adds borderStyle:/borderColor:/titleColor:.
                .alert("alert.title", isPresented: $isPresented) {
                    Button("button.ok") {}
                } message: {
                    Text("alert.message")
                }
                .alert("alert.title", isPresented: $isPresented) {
                    Button("button.ok") {}
                }
                // TUIkit adds style: BETWEEN the colour and the width, which
                // is the case a prefix rule would miss: Swift lets a call skip
                // a defaulted parameter from anywhere, not just the tail.
                .border(.red, width: 2)
                // TUIkit spells this fixedSize(horizontal:vertical:), both
                // defaulted to true — so this means what SwiftUI means.
                .fixedSize()
                // Two fully-defaulted EdgeInsets initialisers exist, so this
                // also pins that the call is not AMBIGUOUS — the symbol diff
                // can see that some overload accepts it, never that exactly
                // one does. (Swift's "fewer defaulted arguments" tie-break
                // picks `init(horizontal:vertical:)`; both are all-zero.)
                .padding(EdgeInsets())
            // Another mid-list default: showsIndicators: sits between the axes
            // and the content closure.
            ScrollView(.vertical) {
                Text("scrolled")
            }
        }
    }
}

// MARK: - Shapes a label diff cannot check

/// Trailing-closure position, `@ViewBuilder`-ness and generic inference: the
/// things that make a call bind or not bind once the labels already match.
@MainActor
private struct ClosureAndGenericShapes: View {
    @State private var quantity = 1
    @State private var isOn = false
    @State private var choice = 0

    var body: some View {
        VStack {
            // The receiver's Actions must be inferable from the closure alone.
            Button("button.save", systemImage: "square.and.arrow.down") {}
            Toggle("toggle.wifi", systemImage: "wifi", isOn: $isOn)
            Picker("picker.theme", systemImage: "paintpalette", selection: $choice) {
                Text("picker.light").tag(0)
                Text("picker.dark").tag(1)
            }
            // A value bound through a format style, not a String.
            TextField("field.quantity", value: $quantity, format: .number)
            LabeledContent("row.quantity", value: quantity, format: .number)
        }
        .frame(maxWidth: .infinity, alignment: .leadingFirstTextBaseline)
    }
}

// MARK: - Nested type names SwiftUI source spells out

/// SwiftUI nests these under `Text`, and its own documentation writes them that
/// way. Both are top-level types here, so the nested spellings only compile
/// because of the typealiases on ``Text`` — which is precisely the kind of
/// difference `api_parity.py` cannot see, both names being present somewhere.
@MainActor
private struct NestedTypeSpellings: View {
    private let mode: Text.TruncationMode = .middle
    private let casing: Text.Case = .uppercase
    private let weight: Font.Weight = .bold

    var body: some View {
        Text("text.body")
            .truncationMode(mode)
            .textCase(casing)
            .fontWeight(weight)
    }
}

// MARK: - Labels TUIkit once spelled differently

/// Each of these was a label deviation: the capability existed, but SwiftUI's
/// spelling of the call did not bind to it. A trailing closure hides the label,
/// so each passes its closure as a labelled argument, which is how the
/// difference showed.
@MainActor
private struct FormerLabelDeviations: View {
    var body: some View {
        Text("text.body")
            .onHover(perform: { isHovered in _ = isHovered })
    }
}

// MARK: - A custom modifier, as SwiftUI's documentation writes one

/// The `BorderedCaption` example from SwiftUI's `ViewModifier` documentation,
/// with only the rounded-rectangle overlay swapped for a border. Until
/// 2026-10-03 TUIkit's `ViewModifier` was a buffer transform with no
/// `body(content:)`, so this — the most common custom-modifier shape there is —
/// did not compile.
@MainActor
private struct BorderedCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .padding(1)
            .border(.blue)
    }
}

extension View {
    @MainActor
    fileprivate func borderedCaption() -> some View {
        modifier(BorderedCaption())
    }
}

@MainActor
private struct UsesBorderedCaption: View {
    var body: some View {
        Text("Downtown Bus")
            .borderedCaption()
            .modifier(BorderedCaption().concat(EmptyModifier()))
    }
}

// MARK: - Button styles under SwiftUI's names

/// SwiftUI's built-in styles are primitive styles and their names live there;
/// a style written as a value must not be ambiguous between the two
/// `buttonStyle(_:)` overloads; and the documented `Button(configuration)`
/// pattern must bind.
@MainActor
private struct RedBorderedButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .border(.red)
    }
}

@MainActor
private struct ButtonStyleNames: View {
    var body: some View {
        VStack {
            Button("button.save") {}.buttonStyle(.bordered)
            Button("button.save") {}.buttonStyle(.borderedProminent)
            Button("button.save") {}.buttonStyle(.borderless)
            Button("button.save") {}.buttonStyle(.plain)
            Button("button.save") {}.buttonStyle(PlainButtonStyle())
            Button("button.save") {}.buttonStyle(.link)
            Button("button.save") {}.buttonStyle(RedBorderedButtonStyle())
        }

// MARK: - Key presses

/// SwiftUI's `onKeyPress` in the shapes its documentation and ported code write:
/// a trailing closure that returns a `KeyPress.Result` by implicit member, one
/// that does work first, and the `KeyPress`-taking forms. Until 2026-10-03 the
/// name belonged to TUIkit's focus-blind `(KeyEvent) -> Bool` handler (now
/// `onKeyEvent`), and none of these compiled.
@MainActor
private struct KeyPressShapes: View {
    @State private var count = 0

    var body: some View {
        Text("count")
            .focusable()
            .onKeyPress(.escape) { .handled }
            .onKeyPress(.upArrow) {
                count += 1
                return .handled
            }
            .onKeyPress("q", phases: .down) { press in
                press.modifiers.contains(.control) ? .handled : .ignored
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                count += press.key == .leftArrow ? -1 : 1
                return .handled
            }
            .onKeyPress(characters: .decimalDigits, phases: [.down, .repeat]) { press in
                count = Int(press.characters) ?? count
                return .handled
            }
            .onKeyPress(phases: .all) { press in
                print(press.characters, press.phase == .down)
                return .ignored
            }
            .onKeyPress { _ in .ignored }
    }
}

/// The commands take an OPTIONAL closure, so the trailing-closure form has to
/// bind through the optional, and `nil` has to be spellable.
@MainActor
private struct CommandShapes: View {
    @State private var row = 0

    var body: some View {
        Text("rows")
            .focusable()
            .onMoveCommand { direction in
                if direction == .down { row += 1 }
            }
            .onExitCommand { row = 0 }
            .onDeleteCommand(perform: nil)
    }
}

/// SwiftUI's `dropDestination(for:isEnabled:action:)`, whose action returns
/// nothing, beside TUIkit's `(for:action:isTargeted:)`, whose action answers
/// whether it took the drop: each closure shape has to reach its own.
@MainActor
private struct DropDestinationShapes: View {
    @State private var titles: [String] = []
    let acceptsTitles: Bool

    var body: some View {
        VStack {
            Text("enabled")
                .dropDestination(for: String.self, isEnabled: acceptsTitles) { dropped, session in
                    titles += dropped
                    _ = session.location
                }
            Text("void")
                .dropDestination(for: String.self) { dropped, _ in
                    titles += dropped
                }
            Text("answering")
                .dropDestination(for: String.self) { dropped, _ in
                    titles += dropped
                    return !dropped.isEmpty
                }
        }
    }
}

/// The optional `keyboardShortcut` overload beside the non-optional one, which
/// a conditional shortcut reaches through `nil`, and the localization form.
@MainActor
private struct KeyboardShortcutShapes: View {
    let isPrimary: Bool

    var body: some View {
        VStack {
            Button("Save") {}
                .keyboardShortcut(isPrimary ? .defaultAction : nil)
            Button("Align Left") {}
                .keyboardShortcut("{", modifiers: .option, localization: .withoutMirroring)
            Button("Close") {}
                .keyboardShortcut(.cancelAction)
        }
    }

    var shortcutKey: KeyEquivalent { KeyboardShortcut("s").key }
}
