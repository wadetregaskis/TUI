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

import Foundation
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
    }
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

/// Key-press phases, modifier keys and undo (decisions A4, B7, A1): `.up`, a
/// release handler, the two modifier-key modifiers as SwiftUI's documentation
/// writes them, the lock and keypad modifiers, and `\.undoManager` registering
/// an inverse with a trailing closure.
@MainActor
private struct KeyboardStateShapes: View {
    @State private var peeking = false
    @State private var showsDetails = false
    @Environment(\.undoManager) private var undoManager

    private final class Store {
        var items: [String] = []
    }

    private let store = Store()

    var body: some View {
        VStack {
            Text("peek")
                .focusable()
                .onKeyPress(.space, phases: .up) { _ in
                    peeking = false
                    return .handled
                }
                .onKeyPress(keys: [.space], phases: [.down, .up]) { press in
                    peeking = press.phase == .down
                    return .handled
                }
                .onKeyPress { press in
                    press.modifiers.contains(.capsLock) || press.modifiers.contains(.numericPad)
                        ? .handled : .ignored
                }
            Button("Go Forward") {}
                .keyboardShortcut(.rightArrow)
                .modifierKeyAlternate(.option) {
                    Button("Go to Page…") {}
                }
                .modifierKeyAlternate([.option, .shift]) {
                    Button("Go to Start") {}
                }
            Text("details")
                .onModifierKeysChanged(mask: .option) { old, new in
                    showsDetails = new.contains(.option) && !old.contains(.option)
                }
                .onModifierKeysChanged { _, new in
                    print(new)
                }
            Button("Add") {
                store.items.append("item")
                undoManager?.registerUndo(withTarget: store) { $0.items.removeLast() }
                undoManager?.setActionName("Add")
            }
            .buttonRepeatBehavior(.disabled)
        }
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

#if canImport(UniformTypeIdentifiers)
    import Foundation
    import UniformTypeIdentifiers

    /// SwiftUI's item-provider drag and drop, as its documentation writes it: a
    /// struct delegate holding a binding, both `onDrop` closures, `onDrag`.
    @MainActor
    private struct TextDropDelegate: DropDelegate {
        @Binding var text: String

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }

        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

        func performDrop(info: DropInfo) -> Bool {
            text = "\(info.itemProviders(for: [.text]).count) at \(info.location.x)"
            return true
        }
    }

    @MainActor
    private struct ItemProviderShapes: View {
        @State private var text = ""
        @State private var isTargeted = false

        var body: some View {
            VStack {
                Text("source").onDrag { NSItemProvider(object: "x" as NSString) }
                Text("plain").onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
                    !providers.isEmpty
                }
                Text("located").onDrop(of: [.text], isTargeted: nil) { providers, location in
                    text = "\(providers.count) at \(location.x)"
                    return true
                }
                Text("delegate").onDrop(of: [.text], delegate: TextDropDelegate(text: $text))
            }
        }
    }
#endif

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

/// The content levels and the roles as shape styles, as SwiftUI spells them.
@MainActor
private struct SemanticShapeStyleShapes: View {
    var body: some View {
        VStack {
            VStack {
                Text("title")
                Label("detail", systemImage: "star").foregroundStyle(.secondary)
                Divider().foregroundStyle(.separator)
            }
            .foregroundStyle(.red, .blue)
            HStack { Text("a") }.foregroundStyle(.tertiary)
            HStack { Text("b") }.foregroundStyle(.tint)
            HStack { Text("c") }.foregroundStyle(.red.secondary)
            HStack { Text("d") }.foregroundStyle(.primary, .secondary, .quinary)
            Color.clear.background(.selection)
            HStack { Text("e") }.foregroundStyle(HierarchicalShapeStyle.secondary)
        }
        .foregroundStyle(.foreground)
    }
}

/// Colours from components, as SwiftUI writes them, and read back as numbers.
@MainActor
private struct ColourComponentShapes: View {
    @Environment(\.self) private var environment

    var body: some View {
        let brand = Color(red: 0.2, green: 0.4, blue: 0.6)
        let resolved = brand.resolve(in: environment)
        return VStack {
            Text("rgb").foregroundStyle(brand)
            Text("p3").foregroundStyle(Color(.displayP3, red: 1, green: 0.3, blue: 0, opacity: 0.8))
            Text("grey").foregroundStyle(Color(white: 0.4))
            Text("hsb").foregroundStyle(Color(hue: 0.6, saturation: 0.5, brightness: 0.9))
            Text(resolved.description).foregroundStyle(Color(resolved))
            Text("linear \(resolved.linearRed)").foregroundStyle(resolved)
        }
    }
}

/// Text scales, on a view and on a text, and the nested type names spelled out.
@MainActor
private struct TextScaleShapes: View {
    var body: some View {
        VStack {
            Text("Title").font(.headline)
            Text("Subtitle").textScale(.secondary)
            Text("Long title").truncationMode(Text.TruncationMode.middle).textCase(Text.Case.uppercase)
        }
        .textScale(.secondary, isEnabled: true)
    }
}

/// The two font designs a terminal draws, and a system font by style.
@MainActor
private struct FontDesignShapes: View {
    var body: some View {
        VStack {
            Text("code").fontDesign(.monospaced)
            Text("body").font(.system(.body, design: .default, weight: .semibold))
        }
        .fontDesign(nil)
    }
}

/// An app-wide model injected on the scene, as SwiftUI's Observation docs write it.
@Observable
private final class CorpusLibrary {
    var books: [String] = []
}

private struct CorpusLibraryApp: App {
    @State private var library = CorpusLibrary()

    var body: some Scene {
        WindowGroup {
            Text("Library")
        }
        .environment(library)
        .environment(\.lineSpacing, 1)
        .transformEnvironment(\.locale) { _ in }
    }
}

/// A scaled metric, in the floating-point form SwiftUI's examples use.
@MainActor
private struct ScaledMetricShapes: View {
    @ScaledMetric var iconSize: Double = 20
    @ScaledMetric(relativeTo: .headline) var spacing: Double = 4

    var body: some View {
        Text("size \(iconSize) spacing \(spacing)")
    }
}

/// A scene built from one expression, which SceneBuilder passes through.
private struct ExpressionSceneApp: App {
    var body: some Scene {
        WindowGroup { Text("one") }
    }
}

/// A button that spans its container, and a style that reads the sizing.
@MainActor
private struct ButtonSizingShapes: View {
    @Environment(\.buttonSizing) private var buttonSizing

    var body: some View {
        VStack {
            Button("Open Document…") {}
                .buttonSizing(.flexible)
            Button("Fit") {}.buttonSizing(buttonSizing == .flexible ? .fitted : .automatic)
        }
    }
}

/// The macOS 26 slider: a neutral value, enabled bounds, a current-value label,
/// ticks from a builder and per step, and a hidden thumb.
@MainActor
private struct SliderTickShapes: View {
    @State private var balance = 0.0
    @State private var percentage = 0.5
    @State private var level = 3.0
    let showsHalf: Bool

    var body: some View {
        VStack {
            Slider(value: $balance, in: -1...1, neutralValue: 0) {
                Text("Balance")
            }
            Slider(value: $percentage, enabledBounds: 0.1...0.9) {
                Text("Percentage")
            } currentValueLabel: {
                Text("\(Int(percentage * 100))%")
            } ticks: {
                SliderTickContentForEach(Array(stride(from: 0.0, through: 1.0, by: 0.25)), id: \.self) { value in
                    SliderTick(value) { Text("\(Int(value * 100))") }
                }
                if showsHalf {
                    SliderTick("half", 0.5)
                }
            }
            Slider(value: $level, in: 0...5, step: 1) {
                Text("Level")
            } tick: { SliderTick($0) }
            .sliderThumbVisibility(.hidden)
        }
    }
}

/// Copy, cut and paste of values, as SwiftUI's Transferable-era modifiers spell them.
@MainActor
private struct TransferShapes: View {
    @State private var names: [String] = ["Ada"]

    var body: some View {
        VStack {
            List(names, id: \.self) { Text($0) }
                .copyable(names)
                .cuttable(for: String.self) {
                    defer { names = [] }
                    return names
                }
                .pasteDestination(for: String.self) { names += $0 } validator: { $0.filter { !$0.isEmpty } }
            PasteButton(payloadType: String.self) { names += $0 }
        }
    }
}

/// An editor that reports its selection, read as SwiftUI's example reads it.
@available(macOS 15, *)
@MainActor
private struct TextSelectionShapes: View {
    @State private var text = ""
    @State private var selection: TextSelection?

    var body: some View {
        VStack {
            TextEditor(text: $text, selection: $selection)
            if case .selection(let range)? = selection?.indices, !(selection?.isInsertion ?? true) {
                Text(text[range])
            }
        }
        .textSelectionAffinity(.upstream)
    }
}

/// Text fields on either axis, in each initialiser shape, as SwiftUI's
/// documentation writes them.
@MainActor
private struct TextFieldAxisShapes: View {
    @State private var title = ""
    @State private var notes = ""
    let caption: String

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...)
            TextField(caption, text: $notes, axis: .vertical)
                .lineLimit(...3)
            TextField("Notes", text: $notes, prompt: Text("Anything else?"), axis: .vertical)
                .lineLimit(1...3)
            TextField(caption, text: $notes, prompt: Text("Anything else?"), axis: .horizontal)
            TextField(text: $notes, prompt: Text("Required"), axis: .vertical) {
                Text("Notes")
            }
            TextField(text: $notes, axis: .vertical) { Text("Notes") }
                .lineLimit(5, reservesSpace: true)
        }
    }
}

/// Text fields that report their selection, as SwiftUI's examples write them.
@available(macOS 15, *)
@MainActor
private struct TextFieldSelectionShapes: View {
    @State private var message = ""
    @State private var selection: TextSelection? = nil
    let caption: String

    var body: some View {
        VStack {
            TextField("Message", text: $message, selection: $selection)
            TextField(caption, text: $message, selection: $selection, prompt: Text("Say hello"))
            TextField("Message", text: $message, selection: $selection, axis: .vertical)
                .lineLimit(2...4)
            TextField(text: $message, selection: $selection) {
                Text("Message")
            }
            TextField(text: $message, selection: $selection, prompt: Text("Say hello"), axis: .vertical) {
                Text("Message")
            }
        }
        .textSelectionAffinity(.downstream)
    }
}

/// Text sized by each of SwiftUI's line-limit range forms.
@MainActor
private struct LineLimitRangeShapes: View {
    let summary: String

    var body: some View {
        VStack {
            Text(summary).lineLimit(2...4)
            Text(summary).lineLimit(3...)
            Text(summary).lineLimit(...2)
        }
    }
}

/// A number formatted through a printf-style specifier inside a Text literal.
@MainActor
private struct SpecifierShapes: View {
    let price: Double
    let count: Int

    var body: some View {
        Text("Total: \(price, specifier: "%.2f") for \(count, specifier: "%d") items")
    }
}

/// Remote images in the three forms SwiftUI's documentation shows.
@MainActor
private struct AsyncImageShapes: View {
    let url = URL(string: "https://example.com/icon.png")

    var body: some View {
        VStack {
            AsyncImage(url: url)
            AsyncImage(url: url) { image in
                image
            } placeholder: {
                ProgressView()
            }
            AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                switch phase {
                case .success(let image): image
                case .failure: Text("No image")
                case .empty: ProgressView()
                @unknown default: EmptyView()
                }
            }
        }
    }
}

/// Interpolation quality and antialiasing set on the image itself.
@MainActor
private struct ImageInterpolationShapes: View {
    var body: some View {
        VStack {
            Image(systemName: "star").interpolation(.none)
            Image(systemName: "star").interpolation(.high).antialiased(false)
        }
    }
}

/// An icon drawn as a template in the surrounding foreground.
@MainActor
private struct TemplateImageShapes: View {
    var body: some View {
        Image(systemName: "star").renderingMode(.template).foregroundStyle(.tint)
    }
}

#if canImport(AppKit)
    import AppKit
    import TUIkitAppKit

    /// Colours to and from AppKit's and Core Graphics' own.
    @MainActor
    private struct AppKitColourShapes: View {
        let nsColor: NSColor
        let cgColor: CGColor

        var body: some View {
            VStack {
                Text("bridge.ns").foregroundStyle(Color(nsColor: nsColor))
                Text("bridge.cg").foregroundStyle(Color(cgColor: cgColor))
            }
            .onAppear {
                _ = NSColor(Color.red)
                _ = Color.red.resolve(in: EnvironmentValues()).cgColor
            }
        }
    }

    /// Images made from a Core Graphics image or an AppKit image.
    @MainActor
    private struct CoreGraphicsImageShapes: View {
        let cgImage: CGImage
        let nsImage: NSImage

        var body: some View {
            VStack {
                Image(cgImage, scale: 2, orientation: .right, label: Text("Photo"))
                Image(decorative: cgImage, scale: 1)
                Image(nsImage: nsImage).resizable().scaledToFit()
            }
        }
    }
#endif

/// Images named by a resource in a bundle.
@MainActor
private struct BundleImageShapes: View {
    var body: some View {
        VStack {
            Image("logo")
            Image("logo", bundle: nil, label: Text("Logo"))
            Image(decorative: "divider", bundle: nil)
        }
    }
}

/// A view's task on a task executor of the app's.
@available(macOS 15, *)
@MainActor
private struct ExecutorTaskShapes: View {
    let executor: any TaskExecutor
    @State private var status = ""

    var body: some View {
        Text(status)
            .task(id: 1, name: "status", executorPreference: executor) {
                status = "ready"
            }
            .task(id: 2, executorPreference: executor, priority: .low) {}
    }
}

/// A sliding label clipped to its frame, and a faded compositing group.
@MainActor
private struct ClippingShapes: View {
    var body: some View {
        VStack {
            Text("Sliding").offset(x: 4).frame(width: 20).clipped()
            ZStack {
                Text("Composited")
                Text("Group")
            }
            .compositingGroup()
            .opacity(0.9)
            Text("Edge").clipped(antialiased: true)
        }
    }
}

/// A title kept clear of the container's corner, as SwiftUI's documentation
/// writes it.
@MainActor
private struct CornerInsetShapes: View {
    var body: some View {
        GeometryReader { geometry in
            Text("Title").offset(x: geometry.containerCornerInsets.topLeading.width)
        }
    }
}

/// Resizable images: stretched, fitted, and in slices.
@MainActor
private struct ResizableImageShapes: View {
    var body: some View {
        VStack {
            Image(systemName: "star").resizable().frame(width: 20, height: 4)
            Image(systemName: "star").resizable().scaledToFit()
            Image(systemName: "star")
                .resizable(capInsets: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), resizingMode: .tile)
        }
    }
}

// MARK: - Table columns

/// SwiftUI's column surface as its documentation writes it: key-path and
/// view-content columns, a sortable table holding a column that cannot sort,
/// `sortUsing:` with a `SortDescriptor` order, a `Text` label, an `if`, a
/// `Group`, columns factored into a builder property, and `TableColumnForEach`.
/// `KeyPathComparator` and `SortDescriptor` are Foundation's, which SwiftUI
/// re-exports and TUIkit does not; this file imports it above.
@MainActor
private struct TableColumnShapes: View {
    struct Person: Identifiable {
        let id: Int
        var givenName: String
        var familyName: String
        var age: Int
        var email: String
    }

    @State private var people: [Person] = []
    @State private var selection: Person.ID?
    @State private var selections = Set<Person.ID>()
    @State private var sortOrder = [KeyPathComparator(\Person.givenName)]
    @State private var descriptors = [SortDescriptor(\Person.age)]
    let showsEmail: Bool

    var body: some View {
        VStack {
            Table(people) {
                TableColumn("Given Name", value: \.givenName)
                    .width(min: 40, ideal: 90, max: 200)
                TableColumn("Age") { person in Text("\(person.age)") }
                    .width(60)
            }
            Table(people, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Given Name", value: \.givenName)
                TableColumn("Family Name", value: \.familyName) { Text($0.familyName) }
                TableColumn("Age", value: \.age) { Text($0.age, format: .number) }
                    .alignment(.numeric)
                TableColumn("Notes") { _ in Text("-") }
                if showsEmail {
                    TableColumn("Email", value: \.email)
                }
                // SwiftUI cannot infer a key path's root here either.
                Group {
                    TableColumn(Text("Label"), value: \Person.email)
                }
            }
            .onChange(of: sortOrder) { _, newOrder in people.sort(using: newOrder) }
            Table(people, selection: $selections, sortOrder: $descriptors) {
                TableColumn("Age", sortUsing: SortDescriptor(\Person.age)) { Text("\($0.age)") }
            }
            .tableColumnHeaders(.hidden)
            .alternatingRowBackgrounds()
            .tableStyle(.inset)
            Table(people) { TableColumn("Name", value: \.givenName) }
                .tableStyle(.bordered)
            Table(people) { TableColumn("Name", value: \.givenName) }
                .tableStyle(PaddedTableStyle())
            List(people) { Text($0.givenName) }
                .alternatingRowBackgrounds(.disabled)
            Table(people) {
                Group {
                    TableColumn("Label", value: \Person.email)
                }
                nameColumns
                TableColumnForEach(0..<2) { index in
                    TableColumn("Column \(index)") { (person: Person) in Text(person.givenName) }
                }
            }
        }
    }

    @TableColumnBuilder<Person, Never>
    private var nameColumns: some TableColumnContent<Person, Never> {
        TableColumn("Given", value: \.givenName)
        TableColumn("Family", value: \.familyName)
    }
}

/// Column customization as SwiftUI's documentation writes it: persisted in
/// scene storage with no default written, bound through `State`, columns with
/// identifiers, a default visibility, and a disabled behavior.
@MainActor
private struct TableCustomizationShapes: View {
    struct BugReport: Identifiable {
        let id: Int
        var title: String
        var reporter: String
    }

    @SceneStorage("BugReportTableConfig")
    private var columnCustomizationData: TableColumnCustomization<BugReport>
    @State private var columnCustomization = TableColumnCustomization<BugReport>()
    @State private var reports: [BugReport] = []
    @State private var selection = Set<BugReport.ID>()
    @State private var sortOrder = [KeyPathComparator(\BugReport.title)]

    var body: some View {
        VStack {
            Table(reports, columnCustomization: $columnCustomization) {
                TableColumn("Title", value: \.title)
                    .customizationID("title")
                    .disabledCustomizationBehavior(.visibility)
                TableColumn("Reporter", value: \.reporter)
                    .customizationID("reporter")
                    .defaultVisibility(.hidden)
            }
            Table(
                reports, selection: $selection, sortOrder: $sortOrder,
                columnCustomization: $columnCustomization
            ) {
                TableColumn("Title", value: \.title).customizationID("title")
            }
            Table(of: BugReport.self, columnCustomization: $columnCustomization) {
                TableColumn("Title", value: \.title).customizationID("title")
            } rows: {
                ForEach(reports)
            }
        }
        .onAppear {
            columnCustomization = columnCustomizationData
            columnCustomization[visibility: "reporter"] = .visible
            columnCustomization.resetOrder()
        }
    }
}

/// SwiftUI's row surface: a table whose rows come from a row builder, with a
/// fixed row, `ForEach` in both forms, an `if`, a `Group`, and row content
/// factored into a type of the app's own.
@MainActor
private struct TableRowShapes: View {
    struct Purchase: Identifiable {
        let id: Int
        var item: String
        var price: Double
    }

    struct Specials: TableRowContent {
        let purchases: [Purchase]

        @TableRowBuilder<Purchase>
        var tableRowBody: some TableRowContent<Purchase> {
            ForEach(purchases) { purchase in
                TableRow(purchase)
            }
        }
    }

    @State private var purchases: [Purchase] = []
    @State private var selection: Purchase.ID?
    @State private var sortOrder = [KeyPathComparator(\Purchase.item)]
    let showsTotal: Bool

    var body: some View {
        VStack {
            Table(of: Purchase.self) {
                TableColumn("Item", value: \.item)
                TableColumn("Price") { Text($0.price, format: .number) }
            } rows: {
                TableRow(Purchase(id: 0, item: "Coffee", price: 2.5))
                ForEach(purchases) { TableRow($0) }
                ForEach(purchases)
                    .selectionDisabled()
                ForEach(purchases) { purchase in
                    TableRow(purchase)
                        .selectionDisabled(purchase.price == 0)
                        .onHover { hovering in print(purchase.item, hovering) }
                }
                if showsTotal {
                    TableRow(Purchase(id: -1, item: "Total", price: 0))
                }
                Group {
                    Specials(purchases: purchases)
                }
            }
            Table(selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Item", value: \.item)
            } rows: {
                ForEach(purchases) { TableRow($0) }
            }
        }
    }
}

// MARK: - Hierarchical tables

private struct TableOutlineShapes: View {
    struct File: Identifiable {
        let id: Int
        var name: String
        var children: [Self]?
    }

    @State private var files: [File] = []
    @State private var selection: File.ID?
    @State private var picked = Set<File.ID>()
    @State private var sortOrder = [KeyPathComparator(\File.name)]
    @State private var customization = TableColumnCustomization<File>()
    @State private var showsDownloads = false

    var body: some View {
        VStack {
            Table(files, children: \.children) {
                TableColumn("Name", value: \.name)
            }
            Table(files, children: \.children, selection: $selection) {
                TableColumn("Name", value: \.name)
            }
            Table(
                files, children: \.children, selection: $picked, sortOrder: $sortOrder,
                columnCustomization: $customization
            ) {
                TableColumn("Name", value: \.name)
            }
            Table(of: File.self) {
                TableColumn("Name", value: \.name)
            } rows: {
                DisclosureTableRow(File(id: 0, name: "Downloads"), isExpanded: $showsDownloads) {
                    ForEach(files) { TableRow($0) }
                }
                DisclosureTableRow(File(id: 1, name: "Archive")) {
                    TableRow(File(id: 2, name: "old"))
                }
                OutlineGroup(files, children: \.children)
                OutlineGroup(File(id: 3, name: "root"), children: \.children)
                OutlineGroup(files, children: \.children) { file in
                    TableRow(file)
                }
            }
        }
    }
}

private struct PaddedTableStyle: TableStyle {
    func makeBody(configuration: Configuration) -> some View {
        InsetTableStyle().makeBody(configuration: configuration)
            .padding()
    }
}
// MARK: - Live time text

/// Dates and timers that keep themselves up to date, written as SwiftUI's
/// documentation writes them — the styles, the timer interval with its pause,
/// and both inside a localized literal.
@MainActor
private struct LiveTimeTextShapes: View {
    let event: Date
    let start: Date

    var body: some View {
        VStack {
            Text(event, style: .relative)
            Text(event, style: .time)
            Text(event, style: .date)
            Text(event, style: .offset)
            Text(event, style: .timer)
            Text(
                timerInterval: Date.now...Date(timeInterval: 12 * 60, since: .now),
                pauseTime: Date.now + (10 * 60))
            Text(timerInterval: start...event, countsDown: false, showsHours: false)
            Text("Ends \(event, style: .relative)")
            Text("Left: \(timerInterval: start...event, pauseTime: nil, countsDown: true)")
            Text(event, style: .relative).textVariant(.fixed)
        }
    }
}

/// The system formats over a time data source. On macOS SwiftUI's own
/// `.offset(to:)` and the rest are visible here too, through AppKit; every one
/// of these must still bind to TUIkit's (`SystemFormatStyle+DiscreteStatics`).
@available(macOS 15, *)
@MainActor
private struct TimeDataSourceShapes: View {
    let startDate: Date

    var body: some View {
        VStack {
            Text(.currentDate, format: .offset(to: startDate))
            Text(.currentDate, format: .offset(to: startDate, sign: .always()))
            Text(.currentDate, format: .stopwatch(startingAt: startDate))
            Text(.currentDate, format: .dateTime)
            Text(.durationOffset(to: startDate), format: .time(pattern: .minuteSecond))
            Text(.currentDate, format: .reference(to: startDate, allowedFields: [.hour, .minute], thresholdField: .hour))
            Text(.currentDate, format: .timer(countingDownIn: startDate..<startDate + 60, maxPrecision: .milliseconds(10)))
            Text(.currentDate, format: .timer(countingUpIn: startDate..<startDate + 60))
            Text(Date.now, format: .offset(to: startDate))
            Text("Started \(Date.now, format: .reference(to: startDate))")
        }
    }
}
// MARK: - Wave 12: animation and transitions

/// SwiftUI's own `Transition` example, and the built-ins in both spellings —
/// the generic overload must not make the `AnyTransition` ones ambiguous.
private struct RotatingFadeTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1.0 : 0.0)
            .offset(x: Int(phase.value) * 3)
    }
}

@MainActor
private struct TransitionShapes: View {
    @State private var isShown = false

    var body: some View {
        VStack {
            if isShown {
                Text("custom").transition(RotatingFadeTransition())
                Text("any").transition(.move(edge: .top).combined(with: .opacity))
                Text("typed").transition(.push(from: .leading))
                Text("scaled").transition(.scale(0.5, anchor: .bottom))
                Text("scale").transition(.scale)
                Text("slide").transition(.slide)
                Text("asym").transition(.asymmetric(insertion: .opacity, removal: .slide))
                Text("typed asym").transition(
                    AsymmetricTransition(insertion: .opacity, removal: .move(edge: .bottom)))
                Text("erased").transition(AnyTransition(RotatingFadeTransition()).animation(.smooth))
                Text("combined").transition(
                    RotatingFadeTransition().combined(with: .move(edge: .leading)).animation(.bouncy))
                Text("any scale").transition(.scale(scale: 0.2, anchor: .center))
                Text("identity").transition(.identity)
                Text("offset").transition(.offset(x: 2, y: 1))
            }
        }
    }
}

/// A custom transaction value, SwiftUI's own documentation example.
private struct MyTransactionKey: TransactionKey {
    static let defaultValue = false
}

extension Transaction {
    fileprivate var myCustomValue: Bool {
        get { self[MyTransactionKey.self] }
        set { self[MyTransactionKey.self] = newValue }
    }
}

/// Completions, custom transaction values, scoped transactions and content
/// transitions, as SwiftUI's documentation writes them.
@MainActor
private struct TransactionShapes: View {
    @State private var isActive = false
    @State private var count = 0

    var body: some View {
        VStack {
            Text("\(count)")
                .contentTransition(.numericText(value: Double(count)))
            Text("active")
                .transaction { transaction in
                    if transaction.myCustomValue {
                        transaction.animation = .default.repeatCount(3)
                    }
                }
                .transaction { transaction in
                    transaction.animation = transaction.animation?.speed(2)
                } body: { content in
                    content.opacity(isActive ? 1.0 : 0.0)
                }
                .animation(.easeInOut) { content in
                    content.opacity(isActive ? 1.0 : 0.5)
                }
                .transition(.modifier(active: FadeModifier(amount: 0), identity: FadeModifier(amount: 1)))
            Button("Toggle") {
                withTransaction(\.myCustomValue, true) {
                    isActive.toggle()
                }
                withAnimation(.easeOut(duration: 0.3)) {
                    count += 1
                } completion: {
                    isActive = false
                }
                withAnimation(.bouncy, completionCriteria: .removed) {
                    count -= 1
                } completion: {}
                var transaction = Transaction(animation: .snappy)
                transaction.addAnimationCompletion { count = 0 }
                transaction.isContinuous = true
                transaction.tracksVelocity = true
                withTransaction(transaction) { count += 2 }
            }
        }
    }
}

private struct FadeModifier: ViewModifier, Animatable {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(amount)
    }
}

/// Springs, unit curves and visual effects, as SwiftUI's documentation writes
/// them.
@MainActor
private struct SpringShapes: View {
    @State private var offset = 0

    var body: some View {
        let spring = Spring(duration: 0.5, bounce: 0.3)
        let (mass, stiffness, damping) = (spring.mass, spring.stiffness, spring.damping)
        let physical = Spring(mass: mass, stiffness: stiffness, damping: damping)
        let position = physical.value(target: 1.0, time: 0.25)
        let curve = UnitCurve.easeInOut
        let inputTime = curve.inverse.value(at: 0.6)
        return Text("\(position) \(inputTime)")
            .visualEffect { content, geometryProxy in
                content
                    .offset(x: geometryProxy.size.width / 4)
                    .opacity(0.8)
                    .grayscale(0.5)
            }
            .animation(.spring(spring, blendDuration: 0.1), value: offset)
            .animation(.interpolatingSpring(spring, initialVelocity: 2), value: offset)
            .animation(.interpolatingSpring(mass: 1, stiffness: 100, damping: 10), value: offset)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: offset)
            .animation(.interactiveSpring, value: offset)
            .animation(.timingCurve(.circularEaseInOut, duration: 0.4), value: offset)
            .animation(.easeIn.logicallyComplete(after: 0.1), value: offset)
    }
}

/// SwiftUI's own keyframe timeline examples, with `Double` for `CGPoint`.
@MainActor
private func keyframeShapes() -> Double {
    struct Values {
        var rotation = Angle.zero
        var scale = 1.0
    }
    let keyframes = KeyframeTimeline(initialValue: 0.0) {
        CubicKeyframe(100, duration: 0.3)
        CubicKeyframe(0, duration: 0.7)
    }
    let tracks = KeyframeTimeline(initialValue: Values()) {
        KeyframeTrack(\.rotation) {
            CubicKeyframe(.zero, duration: 0.2)
            CubicKeyframe(.degrees(45), duration: 0.3)
        }
        KeyframeTrack(\.scale) {
            CubicKeyframe(1.2, duration: 0.5)
            SpringKeyframe(0.9, duration: 0.2, spring: .bouncy)
            LinearKeyframe(1.0, duration: 0.3, timingCurve: .easeOut)
            MoveKeyframe(1.0)
        }
    }
    return keyframes.value(time: 0.45) + tracks.value(progress: 0.5).scale + tracks.duration
}

// MARK: - Pinned section headers and footers

/// SwiftUI's pinned lazy stack, with every spelling of `pinnedViews:`.
@MainActor
private struct PinnedSectionShapes: View {
    let groups: [(name: String, items: [String])] = [("A", ["a1", "a2"]), ("B", ["b1"])]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.items, id: \.self) { Text($0) }
                    } header: {
                        Text(group.name)
                    }
                }
            }
            LazyVStack(pinnedViews: .sectionFooters) {
                Section {
                    Text("row")
                } footer: {
                    Text("footer")
                }
            }
            LazyVStack(pinnedViews: PinnedScrollableViews(rawValue: 3)) {
                Section("Title") { Text("row") }
            }
            // SwiftUI's sectioned grid, `spacing: nil` included.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 12))], alignment: .leading, spacing: nil,
                pinnedViews: [.sectionHeaders, .sectionFooters]
            ) {
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.items, id: \.self) { Text($0) }
                    } header: {
                        Text(group.name)
                    } footer: {
                        Text("\(group.items.count) items")
                    }
                }
            }
        }
    }
}

/// SwiftUI's pinned horizontal stack and grid, sections along a row.
@MainActor
private struct PinnedRowSectionShapes: View {
    let groups: [(name: String, items: [String])] = [("A", ["a1", "a2"]), ("B", ["b1"])]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: nil, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.items, id: \.self) { Text($0) }
                    } header: {
                        Text(group.name)
                    } footer: {
                        Text("end")
                    }
                }
            }
            LazyHStack(pinnedViews: .sectionHeaders) {
                Section("Title") { Text("column") }
            }
            LazyHGrid(
                rows: [GridItem(.fixed(1)), GridItem(.fixed(1))], alignment: .center, spacing: nil,
                pinnedViews: .sectionHeaders
            ) {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items, id: \.self) { Text($0) }
                    }
                }
            }
            LazyHGrid(rows: [GridItem(.flexible())]) { Text("plain") }
        }
    }
}

/// The option set's own surface: an `OptionSet` of `UInt32`.
private func pinnedOptions() -> Bool {
    var pinned: PinnedScrollableViews = [.sectionHeaders, .sectionFooters]
    pinned.remove(.sectionFooters)
    return pinned.contains(.sectionHeaders) && pinned.rawValue == 1 && PinnedScrollableViews().isEmpty
}
// MARK: - Tabs

/// SwiftUI's tab surface as its documentation writes it: `Tab` in its common
/// forms, a `TabSection`, a loop of tabs, conditionals, the tab modifiers, the
/// sidebar style with its customization, and an optional selection whose tabs
/// promote their values.
@MainActor
private struct TabShapes: View {
    enum Pane: Hashable { case inbox, sent, folder(String) }

    @State private var pane = Pane.inbox
    @State private var optionalTab: Int?
    @AppStorage("sidebar") private var customization: TabViewCustomization
    @Environment(\.tabBarPlacement) private var placement
    @Environment(\.isTabBarShowingSections) private var showingSections
    let folders: [String]
    let showsArchive: Bool

    var body: some View {
        VStack {
            TabView(selection: $pane) {
                Tab("Inbox", systemImage: "tray", value: Pane.inbox) { Text("inbox") }
                    .badge(3)
                    .customizationID("inbox")
                Tab("Sent", systemImage: "paperplane", value: .sent) { Text("sent") }
                    .badge("new")
                    .defaultVisibility(.hidden, for: .tabBar)
                    .customizationBehavior(.automatic, for: .tabBar)
                TabSection("Folders") {
                    ForEach(folders, id: \.self) { folder in
                        Tab(folder, systemImage: "folder", value: Pane.folder(folder)) { Text(folder) }
                    }
                }
                .customizationID("folders")
                .sectionActions {
                    Button("Add Folder") {}
                }
                if showsArchive {
                    Tab("Archive", systemImage: "archivebox", value: Pane.folder("archive")) { Text("archive") }
                        .tabPlacement(.sidebarOnly)
                        .disabled(true)
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewCustomization($customization)
            .tabViewSidebarHeader { Text("Mail") }
            TabView {
                Tab("Home", systemImage: "house") { Text("home") }
                Tab(role: .search) { Text("search") }
                Tab {
                    Text("custom")
                } label: {
                    Label("Custom", systemImage: "star")
                }
                Group {
                    Tab("Hidden", systemImage: "eye.slash") { Text("hidden") }
                        .hidden()
                }
            }
            .tabViewStyle(.tabBarOnly)
            TabView(selection: $optionalTab) {
                Tab("One", systemImage: "1.circle", value: 1) { Text("one") }
                TabSection("More") {
                    Tab("Two", systemImage: "2.circle", value: 2) { Text("two") }
                }
            }
            .tabViewStyle(.grouped)
        }
    }
}

// MARK: - List editing and styling

@MainActor
private struct ListStylingShapes: View {
    struct Fruit: Identifiable {
        let id: Int
        var name: String
    }

    @State private var fruit: [Fruit] = []
    @State private var selection: Fruit.ID?
    @State private var picked = Set<Fruit.ID>()
    @State private var expanded = true
    @Environment(\.backgroundProminence) private var backgroundProminence
    @Environment(\.sidebarRowSize) private var sidebarRowSize

    var body: some View {
        VStack {
            List($fruit, editActions: .all) { $item in
                Text(item.name)
            }
            List($fruit, editActions: .delete, selection: $selection) { $item in
                Text(item.name)
            }
            List($fruit, editActions: .move, selection: $picked) { $item in
                Text(item.name)
            }
            List {
                Section("Fruit", isExpanded: $expanded) {
                    ForEach(fruit) { item in
                        Label(item.name, systemImage: "leaf")
                            .listItemTint(.monochrome)
                            .listRowInsets(.horizontal, 2)
                            .badge(2)
                            .badgeProminence(.decreased)
                            .typeSelectEquivalent(item.name)
                            .contextMenu {
                                Button("Eat") {}
                            } preview: {
                                Text(item.name)
                            }
                    }
                }
                .sectionActions {
                    Button("Add", systemImage: "plus") {}
                }
                Section(isExpanded: $expanded) {
                    Text("row")
                        .typeSelectEquivalent(Text("row"))
                } header: {
                    Text("Header")
                }
            }
            .listStyle(.sidebar)
            .listItemTint(.red)
            .environment(\.defaultMinListRowHeight, 2)
            .environment(\.defaultMinListHeaderHeight, 1)
            List(fruit) { Text($0.name) }
                .listStyle(.inset)
            List(fruit) { Text($0.name) }
                .listStyle(.bordered)
            List(fruit) { Text($0.name) }
                .listStyle(.automatic)
        }
    }
}

// MARK: - Table row drag and drop

@MainActor
private struct TableRowDragShapes: View {
    struct Purchase: Identifiable {
        let id: Int
        var item: String
    }

    @State private var purchases: [Purchase] = []
    @State private var basket: [Purchase] = []

    var body: some View {
        VStack {
            Table(of: Purchase.self) {
                TableColumn("Item", value: \.item)
            } rows: {
                ForEach(purchases) { purchase in
                    TableRow(purchase)
                        .draggable(purchase.item)
                        .dropDestination(for: String.self) { items in print(items) }
                }
                .dropDestination(for: String.self) { index, items in print(index, items) }
            }
            Table(of: Purchase.self) {
                TableColumn("Item", value: \.item)
            } rows: {
                ForEach(basket) { purchase in
                    TableRow(purchase)
                        .itemProvider { NSItemProvider(object: purchase.item as NSString) }
                }
                .onInsert(of: [.plainText]) { index, providers in print(index, providers) }
            }
        }
    }
}

/// Labels and an empty state with an icon from an image resource's name.
@MainActor
private struct ImageNameLabelShapes: View {
    var body: some View {
        VStack {
            Label("Settings", image: "gear")
            ContentUnavailableView("No Mail", image: "tray", description: Text("New mail appears here."))
        }
    }
}

/// A font resolved in the environment, to read whether it is bold.
@MainActor
private struct FontResolvedShapes: View {
    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        let resolved = Font.headline.resolve(in: fontContext)
        Text(resolved.isBold ? "Bold" : "Regular").fontWeight(resolved.weight)
    }
}

/// The font in effect, made bold.
@MainActor
private struct DefaultFontShapes: View {
    var body: some View {
        VStack {
            Text("Emphasised").font(.default.bold())
            Text("Inherited").font(.default)
        }
        .font(.headline)
    }
}

/// A view's three animatable properties as one AnimatableValues.
@MainActor
private struct AnimatableValuesShapes: View, Animatable {
    var x: Double
    var y: Double
    var fade: Double

    var animatableData: AnimatableValues<Double, Double, Double> {
        get { AnimatableValues(x, y, fade) }
        set { (x, y, fade) = newValue.value }
    }

    var body: some View {
        Text("Moving").offset(x: Int(x), y: Int(y)).opacity(fade)
    }
}

/// A text editor with find and replace, shown by a toolbar-style toggle.
@MainActor
private struct FindNavigatorShapes: View {
    @State private var text = ""
    @State private var isPresented = false
    @Environment(\.findContext) private var findContext

    var body: some View {
        VStack {
            Toggle("Find", isOn: $isPresented)
            TextEditor(text: $text)
                .replaceDisabled(findContext?.supportsReplace == false)
                .findNavigator(isPresented: $isPresented)
            TextEditor(text: $text).findDisabled()
        }
    }
}
// MARK: - Spring loading

/// SwiftUI's own examples: a button that reveals folders, the modifier
/// overriding an ancestor's value, a tab's own behavior beating its tab
/// view's, and the environment value read back.
@MainActor
private struct SpringLoadingShapes: View {
    @State private var showFolders = false
    @Environment(\.springLoadingBehavior) private var springLoading

    var body: some View {
        VStack {
            HStack {
                Button {
                    showFolders = true
                } label: {
                    Label("Show Folders", systemImage: "folder")
                }
                .springLoadingBehavior(.enabled)
            }
            .springLoadingBehavior(.disabled)
            TabView {
                Tab("Favorites", systemImage: "star") {
                    Text("Favorites")
                }
                .springLoadingBehavior(.enabled)
                Tab("Recents", systemImage: "clock") {
                    Text(springLoading == .automatic ? "automatic" : "set")
                }
            }
            .springLoadingBehavior(.disabled)
        }
    }
}

// MARK: - Drag and drop session values

/// The values of SwiftUI's own session examples, as an app's helpers take
/// them: a phase matched with its operation, the dragged items' identifiers,
/// the configurations a source and a destination build, a formation.
@MainActor
private enum DragSessionValueShapes {
    static func update(_ session: DragSession, remove: ([UUID]) -> Void) {
        if session.phase == .ended(.delete) {
            remove(session.draggedItemIDs(for: UUID.self))
        }
        switch session.phase {
        case .ended(let operation) where operation == .move:
            remove(session.draggedItemIDs(for: UUID.self))
        default:
            break
        }
        print(session.id, session.location, session.draggedItemIndex)
    }

    static func configuration(for session: DropSession) -> DropConfiguration {
        if session.suggestedOperations.contains(.move) {
            return DropConfiguration(operation: .move)
        }
        print(session.phase, session.itemsCount, session.size, session.localSession?.draggedItemIDs(for: UUID.self) ?? [])
        return DropConfiguration(operation: .copy)
    }

    static func makeConfiguration() -> DragConfiguration {
        let operations = DragConfiguration.OperationsOutsideApp(allowCopy: true, allowMove: true)
        _ = DragConfiguration(allowMove: false, allowDelete: true)
        _ = DragConfiguration(
            operationsWithinApp: .init(allowMove: true, allowDelete: true),
            operationsOutsideApp: .init(allowMove: true, allowDelete: true))
        return DragConfiguration(operationsOutsideApp: operations)
    }

    static let formations: [DragDropPreviewsFormation] = [.default, .list, .none, .pile, .stack]
}
// MARK: - Attributed text (Wave 17t)

/// SwiftUI's attributed `Text`, as its documentation writes it. The parity
/// tool cannot see `Text(_:)` for an `AttributedString` — its key collapses
/// onto `Text.init(_:)` — so this is the check. On macOS SwiftUICore's scope
/// is visible here too; the assignments below must still bind to TUIkit's.
@MainActor
private struct AttributedText: View {
    var content: AttributedString {
        var attributedString = AttributedString("Blue text")
        attributedString.foregroundColor = .blue
        attributedString.backgroundColor = .yellow
        attributedString.font = .headline
        attributedString.underlineStyle = .single
        attributedString.strikethroughStyle = .single
        attributedString.swiftUI.foregroundColor = .blue
        attributedString.mergeAttributes(AttributeContainer().foregroundColor(.red))
        return attributedString
    }

    var body: some View {
        VStack {
            Text(content)
            Text(content) + Text("tail").bold()
            Text("Red text")
            Text("")
            Text(" ")
        }
        .foregroundStyle(.red)
    }
}
// MARK: - Gestures

/// SwiftUI's gestures as its documentation writes them: a gesture held in a
/// stored property and in a computed one, `@GestureState` with `updating` and
/// a transaction, the three attaching modifiers in every form, the algebra
/// with its values switched over, an erased and an optional gesture, and a
/// gesture of the app's own.
@MainActor
private struct GestureShapes: View {
    @GestureState private var isDetectingLongPress = false
    @GestureState(resetTransaction: Transaction(animation: .default)) private var isDragging = false
    @GestureState private var selection: Int?
    @State private var completedLongPress = false
    let enabled: Bool

    let newGesture = TapGesture().onEnded {
        print("Tap on VStack.")
    }

    var longPress: some Gesture {
        LongPressGesture(minimumDuration: 3)
            .updating($isDetectingLongPress) { currentState, gestureState, transaction in
                gestureState = currentState
                transaction.animation = Animation.easeIn(duration: 2.0)
            }
            .onEnded { finished in
                self.completedLongPress = finished
            }
    }

    var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in print(value.location, value.startLocation, value.translation, value.time) }
            .onEnded { value in print(value.velocity, value.predictedEndLocation, value.predictedEndTranslation) }
    }

    var body: some View {
        VStack {
            Text("Heart")
                .onTapGesture { print("Tap on image.") }
            Text("Hold")
                .gesture(longPress)
            Text("Drag")
                .gesture(drag, isEnabled: enabled)
            Text("Spatial")
                .gesture(SpatialTapGesture(count: 2).onEnded { event in print(event.location) })
            Text("Sequenced")
                .gesture(
                    LongPressGesture().sequenced(before: DragGesture())
                        .onChanged { value in
                            switch value {
                            case .first(true): print("pressing")
                            case .second(true, let drag): print(drag?.translation as Any)
                            default: break
                            }
                        })
            Text("Exclusive")
                .gesture(
                    TapGesture(count: 2).exclusively(before: TapGesture())
                        .onEnded { value in
                            if case .first = value { print("double") }
                        })
            Text("Simultaneous")
                .gesture(
                    DragGesture().simultaneously(with: LongPressGesture())
                        .onEnded { value in print(value.first as Any, value.second as Any) })
            Text("Erased")
                .gesture(enabled ? AnyGesture(TapGesture()) : AnyGesture(TapGesture(count: 2)))
            Text("Optional")
                .gesture(enabled ? DragGesture() : nil)
            Text("Mapped")
                .gesture(TapGesture().map { 1 }.updating($selection) { value, state, _ in state = value })
            Text("Option-click")
                .gesture(TapGesture().modifiers(.option).onEnded { print("option") })
            Text("Own")
                .gesture(DoubleTapOrDrag().onEnded { _ in print("own") })
        }
        .gesture(newGesture)
        .highPriorityGesture(TapGesture(), including: .subviews)
        .highPriorityGesture(TapGesture(), isEnabled: enabled)
        .highPriorityGesture(TapGesture(), name: "tap")
        .simultaneousGesture(TapGesture().onEnded { print("Gesture on VStack.") })
        .simultaneousGesture(TapGesture(), isEnabled: false)
        .simultaneousGesture(TapGesture(), name: "tap", isEnabled: true)
        .gesture(TapGesture(), including: GestureMask.gesture)
        .gesture(TapGesture(), name: "tap")
        .onLongPressGesture(minimumDuration: 0.5) {
            print("long")
        } onPressingChanged: { pressing in
            print(pressing)
        }
    }

    /// A gesture of the app's own: its value type inferred from its body.
    struct DoubleTapOrDrag: Gesture {
        var body: some Gesture {
            TapGesture(count: 2).exclusively(before: DragGesture())
        }
    }
}

// MARK: - Mesh gradients

/// SwiftUI's own example from `MeshGradient`'s documentation, the mesh as a
/// style and as a view, its other initialisers, and the stored properties an
/// app reads back and edits.
@MainActor
private struct MeshGradientShapes: View {
    @State private var mesh = MeshGradient(width: 3, height: 3, points: [
        .init(0, 0), .init(0.5, 0), .init(1, 0),
        .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
        .init(0, 1), .init(0.5, 1), .init(1, 1)
    ], colors: [
        .red, .purple, .indigo,
        .orange, .white, .blue,
        .yellow, .green, .mint
    ])

    var body: some View {
        VStack {
            mesh
            Text("mesh.text").foregroundStyle(mesh)
            Text("mesh.background").background(
                MeshGradient(
                    width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                    colors: [.red, .blue, .green, .yellow], background: .black, smoothsColors: false,
                    colorSpace: .perceptual))
            MeshGradient(
                width: 2, height: 2,
                bezierPoints: [
                    .init(
                        position: [0, 0], leadingControlPoint: [0, 0], topControlPoint: [0, 0],
                        trailingControlPoint: [0.33, 0.2], bottomControlPoint: [0, 0.33]),
                    .init(
                        position: [1, 0], leadingControlPoint: [0.67, 0.2], topControlPoint: [1, 0],
                        trailingControlPoint: [1, 0], bottomControlPoint: [1, 0.33]),
                    .init(
                        position: [0, 1], leadingControlPoint: [0, 1], topControlPoint: [0, 0.67],
                        trailingControlPoint: [0.33, 1], bottomControlPoint: [0, 1]),
                    .init(
                        position: [1, 1], leadingControlPoint: [0.67, 1], topControlPoint: [1, 0.67],
                        trailingControlPoint: [1, 1], bottomControlPoint: [1, 1]),
                ],
                resolvedColors: [
                    Color.Resolved(red: 1, green: 0, blue: 0), Color.Resolved(red: 0, green: 0, blue: 1),
                    Color.Resolved(red: 0, green: 1, blue: 0), Color.Resolved(red: 1, green: 1, blue: 0),
                ])
            MeshGradient(
                width: 2, height: 2, locations: .points([[0, 0], [1, 0], [0, 1], [1, 1]]),
                colors: .colors([.red, .blue, .green, .yellow]))
        }
        .onAppear {
            if case .points(var points) = mesh.locations {
                points[4] = [0.6, 0.4]
                mesh.locations = .points(points)
            }
            if case .colors(let colors) = mesh.colors {
                mesh.colors = .colors(colors.reversed())
            }
            mesh.smoothsColors.toggle()
            mesh.background = .black
            mesh.colorSpace = .device
            print(mesh.width, mesh.height)
        }
    }
}

// MARK: - Search tokens in the suggestions menu

private enum FruitToken: Hashable, Identifiable, CaseIterable {
    case apple
    case pear
    case banana

    var id: Self { self }
}

/// SwiftUI's own `searchCompletion(_:)` example for a token, and the
/// suggested-tokens form beside it.
@MainActor
private struct SearchTokenSuggestions: View {
    @State private var text = ""
    @State private var tokens: [FruitToken] = []
    @State private var suggested: [FruitToken] = FruitToken.allCases

    var body: some View {
        VStack {
            Text("search.placeholder")
                .searchable(text: $text, tokens: $tokens) { token in
                    switch token {
                    case .apple: Text("Apple")
                    case .pear: Text("Pear")
                    case .banana: Text("Banana")
                    }
                }
                .searchSuggestions {
                    Text("🍎").searchCompletion(FruitToken.apple)
                    Text("🍐").searchCompletion(FruitToken.pear)
                    Text("🍌").searchCompletion(FruitToken.banana)
                }
            Text("search.suggested")
                .searchable(text: $text, tokens: $tokens, suggestedTokens: $suggested) { token in
                    Text(String(describing: token))
                }
        }
    }
}

// MARK: - Split panes bounded by their frames

/// SwiftUI's way of bounding a split pane — a frame on it — and the inspector's
/// width range, which is the same bound.
@MainActor
private struct BoundedSplitPanes: View {
    @State private var showsInspector = true

    var body: some View {
        HSplitView {
            Text("split.sidebar").frame(minWidth: 20, idealWidth: 30, maxWidth: .infinity)
            Text("split.detail").frame(minWidth: 40)
        }
        .inspector(isPresented: $showsInspector) {
            Text("split.inspector").inspectorColumnWidth(min: 20, ideal: 30, max: 50)
        }
    }
}

// MARK: - Reduce motion

/// SwiftUI's way of asking whether to reduce motion, and a transition that
/// says it has none.
@MainActor
private struct ReduceMotionShapes: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showing = false

    private struct Glow: Transition {
        static let properties = TransitionProperties(hasMotion: false)

        func body(content: Content, phase: TransitionPhase) -> some View {
            content.opacity(phase.isIdentity ? 1 : 0)
        }
    }

    var body: some View {
        VStack {
            if showing {
                Text("motion.detail").transition(reduceMotion ? AnyTransition.opacity : .slide)
                Text("motion.glow").transition(Glow())
            }
        }
    }
}
// MARK: - Segmented and palette pickers, date picker styles

@MainActor
private struct D2CPickersAndDates: View {
    @State private var size = 1
    @State private var when = Date()

    var body: some View {
        VStack {
            Picker("Size", selection: $size) {
                Text("S").tag(0)
                Text("M").tag(1)
                Text("L").tag(2)
            }
            .pickerStyle(.segmented)
            Picker("Shape", selection: $size) {
                Image(systemName: "circle").tag(0)
                Image(systemName: "square").tag(1)
            }
            .pickerStyle(.palette)
            .paletteSelectionEffect(.symbolVariant(.fill))
            DatePicker("Starts", selection: $when).datePickerStyle(.stepperField)
            DatePicker("Day", selection: $when, displayedComponents: .date).datePickerStyle(.compact)
        }
    }
}

// MARK: - A tab's own context menu, popovers, drag and drop

private struct D2CPopoverModel: Identifiable {
    var id: String { message }
    let message: String
}

@MainActor
private struct D2CTabInteractions: View {
    @State private var isShowingPopover = false
    @State private var popover: D2CPopoverModel?
    @State private var favourites: [String] = []

    var body: some View {
        TabView {
            Tab("Currently Reading", systemImage: "book") {
                Text("books")
            }
            .contextMenu {
                Button {
                    // Pin this tab.
                } label: {
                    Label("Pin", systemImage: "pin")
                }
                Button {
                    // Open a share sheet to share
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .popover(isPresented: $isShowingPopover) {
                Text("Popover Content")
                    .padding()
            }
            Tab("Popover Anchor", systemImage: "arrow.down") {
                Button("Show Popover") {
                    popover = D2CPopoverModel(message: "Custom Message")
                }
            }
            .popover(item: $popover) { detail in
                Text("\(detail.message)")
                    .padding()
            }
            Tab("Family", systemImage: "list.bullet") {
                Text("family")
            }
            .draggable("family")
            Tab("Favorites", systemImage: "star.fill") {
                Text("favourites")
            }
            .dropDestination(for: String.self) { receivedIds in
                favourites += receivedIds
            }
        }
    }
}

// MARK: - Presentation sizing

@MainActor
private struct D2CPresentationSizing: View {
    @State private var presentInfo = true
    @State private var presentSheet = false

    var body: some View {
        Text("page")
            .sheet(isPresented: $presentInfo) {
                Text("Flower facts")
                    .presentationSizing(
                        .page
                            .fitted(horizontal: false, vertical: true)
                            .sticky(horizontal: false, vertical: true))
            }
            .sheet(isPresented: $presentSheet) {
                Text("Dynamic content")
                    .presentationSizing(.form.sticky(horizontal: false, vertical: true))
            }
            .sheet(isPresented: .constant(false)) {
                Text("Emoji grid")
                    .presentationSizing(.fitted)
            }
            .sheet(isPresented: .constant(false)) {
                Text("Default")
                    .presentationSizing(.automatic)
            }
    }
}
// MARK: - Scroll anchor roles (lane D2S)

/// SwiftUI's own example for the roles — the unlabelled anchor for every case,
/// one opted back out of it — and the three roles one at a time.
@MainActor
private struct ScrollAnchorRoleShapes: View {
    let items = Array(0..<20)

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack {
                    ForEach(items, id: \.self) { Text("\($0)") }
                }
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.topLeading, for: .alignment)
            ScrollView { Text("short") }
                .defaultScrollAnchor(.center, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        }
    }
}

// MARK: - Scroll content background (lane D2S)

/// SwiftUI's own example, its commonest idiom, and `.visible`.
@MainActor
private struct ScrollContentBackgroundShapes: View {
    @State private var notes = ""

    var body: some View {
        VStack {
            List {
                Text("One")
                Text("Two")
                Text("Three")
            }
            .scrollContentBackground(.hidden)
            .background(Color.blue)
            ScrollView { Text("seamless") }
                .scrollContentBackground(.visible)
            TextEditor(text: $notes)
                .scrollContentBackground(.automatic)
        }
    }
}

// MARK: - Scroll target behaviours (lane D2S)

/// A behaviour of the app's own, as SwiftUI's documentation writes one (in
/// cells: `ScrollTarget.rect` is a `CellRect`), reading every member of the
/// contexts it is handed.
private struct SnapToTenths: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let step = max(1, context.containerSize.width / 10)
        target.rect.x = target.rect.x / step * step
        if context.velocity.dy == 0, context.axes.contains(.vertical), context.contentSize.height > 0 {
            target.anchor = context.originalTarget.anchor
        }
        _ = context.isEnabled
    }

    func properties(context: PropertiesContext) -> Properties {
        _ = (context.axes, context.environment.isEnabled)
        return Properties()
    }
}

/// SwiftUI's own examples for paging and view-aligned scrolling, and every
/// spelling of the built-in behaviours.
@MainActor
private struct ScrollTargetBehaviorShapes: View {
    let items = Array(0..<20)

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items, id: \.self) { Text("\($0)") }
                }
            }
            .scrollTargetBehavior(.paging)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(items, id: \.self) { Text("\($0)") }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, 20)
            List(items, id: \.self) { Text("\($0)") }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            ScrollView { Text("x") }
                .scrollTargetBehavior(.viewAligned(anchor: .center))
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always, anchor: nil))
                .scrollTargetBehavior(AnyScrollTargetBehavior(SnapToTenths()))
                .scrollTargetBehavior(ViewAlignedScrollTargetBehavior(limitBehavior: .never))
                .scrollTargetBehavior(PagingScrollTargetBehavior())
                .scrollTargetLayout(isEnabled: false)
        }
    }
}

private func erasedBehaviour() -> Bool {
    let erased = AnyScrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByFew))
    let limits: [ViewAlignedScrollTargetBehavior.LimitBehavior] = [.automatic, .always, .alwaysByFew, .alwaysByOne, .never]
    return erased.base is ViewAlignedScrollTargetBehavior && limits.count == 5
        && ScrollTargetBehaviorProperties() == ScrollTargetBehaviorProperties()
}

// MARK: - Unclipped scroll views (lane D2S)

/// SwiftUI's own example for `scrollClipDisabled`, in cells.
@MainActor
private struct ScrollClipDisabledShapes: View {
    var disabled: Bool
    let colors: [Color] = [.red, .green, .blue, .mint, .teal]

    var body: some View {
        VStack {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(colors, id: \.self) { color in
                        Text("■").foregroundStyle(color)
                    }
                }
            }
            .scrollClipDisabled(disabled)
            ScrollView { Text("x") }
                .scrollClipDisabled()
        }
    }
}
// MARK: - Interactive resize (D6M A5)

/// SwiftUI's own example: throttle a renderer while the window is resized.
@MainActor
private struct InteractiveResizeShapes: View {
    @State private var isResizing = false

    var body: some View {
        Text(isResizing ? "resize.coarse" : "resize.full")
            .onInteractiveResizeChange { isResizing in
                self.isResizing = isResizing
            }
    }
}

// MARK: - String tables (D6M A14)

/// SwiftUI's full localized-text initialiser, and the variable-key idiom its
/// documentation gives.
@MainActor
private struct StringTableShapes: View {
    let someString = "pencil"

    var body: some View {
        VStack {
            Text("onboarding.welcome", tableName: "Onboarding", bundle: .main, comment: "Shown once")
            Text("pencil", comment: "A drawing tool")
            Text(LocalizedStringKey(someString))
        }
    }
}

// MARK: - Asset catalogues (D6M A15)

/// SwiftUI's named colour and image. This file imports `TUIkitAppKit`, so
/// these bind to its declarations (which also read `Assets.car`); the
/// TUIkit-only corpus binds the same calls to TUIkit's.
@MainActor
private struct AssetCatalogShapes: View {
    var body: some View {
        VStack {
            Text("asset.title").foregroundStyle(Color("Brand"))
            Image("Logo", bundle: .main)
            Image("Logo", bundle: nil, label: Text("asset.logo"))
            Image(decorative: "Logo")
        }
        .background(Color("Background", bundle: .main))
    }
}

// MARK: - HDR headroom (D6M A16)

/// SwiftUI's own example of a colour annotated with its headroom.
@MainActor
private struct HeadroomShapes: View {
    var body: some View {
        Text("hdr.title").foregroundStyle(Color(.sRGB, red: 1.83, green: 1.47, blue: 0).headroom(4))
    }
}

// MARK: - Size-dependent text variants (D6M A32)

/// SwiftUI's size-dependent preference on the live texts that have spellings
/// to choose from.
@available(macOS 15, *)
@MainActor
private struct SizeDependentShapes: View {
    let deadline: Date

    var body: some View {
        VStack {
            Text(deadline, style: .relative).textVariant(.sizeDependent)
            Text(.currentDate, format: .offset(to: deadline)).textVariant(.sizeDependent).lineLimit(1)
            Text("Ends \(deadline, style: .offset)").textVariant(.fixed)
        }
    }
}

// MARK: - Symbol effects (D6M A35)

#if canImport(Symbols)
    import Symbols

    /// SwiftUI's own symbol-effect examples, over Apple's Symbols types.
    @MainActor
    private struct SymbolEffectShapes: View {
        @State private var counter = 0
        @State private var showing = true

        var body: some View {
            VStack {
                Image(systemName: "bolt.slash.fill").symbolEffectsRemoved()
                Image(systemName: "folder.fill.badge.person.crop")
                if showing {
                    Image(systemName: "star").transition(.symbolEffect(.appear))
                    Image(systemName: "star.fill").transition(.symbolEffect)
                }
                Image(systemName: counter.isMultiple(of: 2) ? "play" : "pause")
                    .contentTransition(.symbolEffect(.replace))
            }
            .symbolEffect(.pulse)
            .symbolEffect(.bounce, value: counter)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: showing)
        }
    }
#endif
// MARK: - Text selection

/// SwiftUI's `textSelection(_:)` example, as its documentation writes it: on
/// one `Text`, and on a `List` to make every row's text selectable — and a
/// selectability passed through a generic, as a helper view would.
@MainActor
private struct TextSelectabilityShapes: View {
    struct Recipient: Identifiable {
        let id: Int
        let name: String
        let email: String
    }

    let recipients: [Recipient] = []
    let date = Date()

    func selectable<S: TextSelectability>(_ selectability: S) -> some View {
        Text("serial").textSelection(selectability)
    }

    var body: some View {
        VStack {
            Text("Event Invite")
                .font(.title)
            Text(date.formatted(date: .long, time: .shortened))
                .textSelection(.enabled)

            List(recipients) { recipient in
                VStack(alignment: .leading) {
                    Text(recipient.name)
                    Text(recipient.email)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            Button("button.ok") {}.textSelection(.disabled)
            selectable(.disabled)
            if EnabledTextSelectability.allowsSelection, !DisabledTextSelectability.allowsSelection {
                Text("both")
            }
        }
        .navigationTitle("New Invitation")
    }
}

// MARK: - Toolbars

/// SwiftUI's toolbar vocabulary as its documentation writes it: items by
/// placement, a group, spacers, a conditional item, a hidden one, the
/// view-builder form, and toolbar content of the app's own.
@MainActor
private struct ToolbarShapes: View {
    @State private var showDownloads = false
    @State private var editing = false

    private struct EditingItems: ToolbarContent {
        var body: some ToolbarContent {
            ToolbarItem(placement: .confirmationAction) { Button("Done") {} }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
        }
    }

    var body: some View {
        VStack {
            Text("notes")
                .navigationTitle("Notes")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Button("Back") {} }
                    ToolbarItem(placement: .principal) { Text("Inbox") }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("New") {}
                        Button("Share") {}
                    }
                    ToolbarSpacer(.fixed)
                    ToolbarItem(id: "downloads") { Button("Downloads") {} }
                        .hidden(!showDownloads)
                    if editing {
                        EditingItems()
                    } else {
                        ToolbarItem(placement: .secondaryAction) { Button("Edit") { editing = true } }
                    }
                    ToolbarItem(placement: .status) { Text("3 notes") }
                    ToolbarItem(placement: .bottomBar) { Text("hints") }
                }
            Text("more")
                .toolbar {
                    Button("Refresh") {}
                    Button("Filter") {}
                }
        }
    }
}
