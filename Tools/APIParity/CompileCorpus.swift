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
            // Separators (decisions A47): a row's, a section's, and the guides.
            List {
                Section("People") {
                    ForEach(people) { person in
                        HStack {
                            Text(person.givenName)
                            Text(person.familyName)
                                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                                .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                        }
                        .listRowSeparator(.visible, edges: .bottom)
                        .listRowSeparatorTint(.red)
                    }
                }
                .listSectionSeparator(.hidden, edges: .top)
                .listSectionSeparatorTint(nil, edges: .bottom)
            }
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

/// Context menus as SwiftUI's documentation writes them: a row's own, with and
/// without a preview, and one menu for the selection of a table and of a list,
/// with and without a primary action, its closure varying by the set.
@MainActor
private struct TableContextMenuShapes: View {
    struct Person: Identifiable {
        let id: Int
        var givenName: String
        var familyName: String
    }

    @State private var people: [Person] = []
    @State private var selection = Set<Person.ID>()

    var body: some View {
        VStack {
            Table(of: Person.self) {
                TableColumn("Given Name", value: \.givenName)
                TableColumn("Family Name", value: \.familyName)
            } rows: {
                ForEach(people) { person in
                    TableRow(person)
                        .contextMenu {
                            Button("Send Email...") {}
                        }
                }
                ForEach(people) { person in
                    TableRow(person)
                        .contextMenu {
                            Button("Send Email...") {}
                        } preview: {
                            Text(person.givenName)
                        }
                }
            }
            Table(people, selection: $selection) {
                TableColumn("Given Name", value: \.givenName)
            }
            .contextMenu(forSelectionType: Person.ID.self) { items in
                if items.isEmpty {
                    Button("New Item") {}
                } else if items.count == 1 {
                    Button("Copy") {}
                    Button("Delete", role: .destructive) {}
                } else {
                    Button("Copy") {}
                    Button("Delete Selected", role: .destructive) {}
                }
            } primaryAction: { items in
                for item in items { print(item) }
            }
            List(people, selection: $selection) { person in
                Text(person.givenName)
            }
            .contextMenu(forSelectionType: Person.ID.self) { _ in
                Button("Copy") {}
            }
        }
    }
}

/// Sections among a table's rows, in every form SwiftUI's documentation
/// writes for rows: a title, a title and an expansion binding, a header view
/// with and without one, and none — and a section from a loop.
@MainActor
private struct TableSectionShapes: View {
    struct Person: Identifiable {
        let id: Int
        var name: String
    }

    struct Team: Identifiable {
        let id: Int
        var name: String
        var members: [Person]
    }

    @State private var team: [Person] = []
    @State private var teams: [Team] = []
    @State private var showsGuests = true
    @State private var selection = Set<Person.ID>()

    var body: some View {
        Table(of: Person.self, selection: $selection) {
            TableColumn("Name", value: \.name)
        } rows: {
            Section("Team") {
                ForEach(team) { TableRow($0) }
            }
            Section("Guests", isExpanded: $showsGuests) {
                TableRow(Person(id: -1, name: "Visitor"))
            }
            Section {
                ForEach(team) { TableRow($0) }
            } header: {
                Text("Alumni").bold()
            }
            Section(isExpanded: $showsGuests) {
                ForEach(team) { TableRow($0) }
            } header: {
                Text("More")
            }
            Section {
                TableRow(Person(id: -2, name: "Loose"))
            }
            ForEach(teams) { group in
                Section(group.name) {
                    ForEach(group.members) { TableRow($0) }
                }
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

// MARK: - Outlines over a binding to a tree

private struct BindingTreeShapes: View {
    struct Folder: Identifiable {
        let id: Int
        var name: String
        var children: [Self]?
    }

    @State private var folders: [Folder] = []
    @State private var root = Folder(id: 0, name: "root")
    @State private var selection: Folder.ID?
    @State private var required: Folder.ID = 0
    @State private var picked = Set<Folder.ID>()

    var body: some View {
        VStack {
            OutlineGroup($folders, children: \.children) { folder in
                TextField("Name", text: folder.name)
            }
            OutlineGroup($root, children: \.children) { Text($0.wrappedValue.name) }
            OutlineGroup($folders, id: \.id, children: \.children) { Text($0.wrappedValue.name) }
            OutlineGroup($root, id: \.id, children: \.children) { Text($0.wrappedValue.name) }
            List($folders, children: \.children) { Text($0.wrappedValue.name) }
            List($folders, id: \.id, children: \.children) { Text($0.wrappedValue.name) }
            List($folders, children: \.children, selection: $selection) { Text($0.wrappedValue.name) }
            List($folders, children: \.children, selection: $picked) { Text($0.wrappedValue.name) }
            List($folders, children: \.children, selection: $required) { Text($0.wrappedValue.name) }
            List($folders, id: \.id, children: \.children, selection: $selection) { Text($0.wrappedValue.name) }
            List($folders, id: \.id, children: \.children, selection: $picked) { Text($0.wrappedValue.name) }
            List($folders, id: \.id, children: \.children, selection: $required) { Text($0.wrappedValue.name) }
            List {
                Text("Mail").badge(3).badgeProminence(.decreased)
                Section("Inbox") { Text("Unread") }.padding(.leading, 1)
            }
            .bold()
            Picker("Fruit", selection: $required) {
                Section("Fruit") { Text("Apple").tag(0) }
                Section { Text("Kale").tag(1) }
            }
            .pickerStyle(.menu)
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
            // `Text + Text` is deprecated (macOS 26); interpolating keeps the
            // styling, as SwiftUI's own replacement does.
            Text("\(Text(content))\(Text("tail").bold())")
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
// MARK: - Resizable sheets and a live page behind them (lane D7S, A19)

/// SwiftUI's documentation examples for `presentationDragIndicator(_:)`,
/// `presentationContentInteraction(_:)` and
/// `presentationBackgroundInteraction(_:)`.
@MainActor
private struct D7SResizableSheets: View {
    @State private var showSettings = true
    @State private var showDetail = false
    @State private var settingsDetent = PresentationDetent.medium

    var body: some View {
        Text("page")
            .sheet(isPresented: $showSettings) {
                Text("Settings")
                    .presentationDetents([.medium, .large], selection: $settingsDetent)
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.resizes)
            }
            .sheet(isPresented: $showDetail) {
                Text("Detail")
                    .presentationDetents([.height(120), .medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(120)))
                    .presentationContentInteraction(.scrolls)
            }
            .sheet(isPresented: .constant(false)) {
                Text("Live")
                    .presentationDetents([.medium])
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.hidden)
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

// MARK: - The top-row hold (lane SCROLLANCHOR)

/// "Load earlier messages": rows inserted above the ones being read keep the
/// reader's place with no anchor declared, and a change made under "no
/// adjustment" moves them with it — SwiftUI's two halves of the same idiom.
@MainActor
private struct LoadEarlierShapes: View {
    @State private var messages = Array(100..<140)

    var body: some View {
        ScrollView {
            LazyVStack {
                Button("Load earlier") { loadEarlier() }
                ForEach(messages, id: \.self) { Text("message \($0)") }
            }
        }
    }

    private func loadEarlier() {
        guard let first = messages.first else { return }
        messages.insert(contentsOf: (first - 20)..<first, at: 0)
    }

    private func loadEarlierAndShowThem() {
        var transaction = Transaction()
        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        withTransaction(transaction) { loadEarlier() }
    }
}

// MARK: - Scroll indicator flash, phase velocity and bounce (lane SCROLLB)

/// SwiftUI's own example for `scrollIndicatorsFlash(trigger:)`, its
/// `onAppear:` twin, a phase observer reading the velocity, and a bounce under
/// `.always`.
@MainActor
private struct ScrollFlashPhaseBounceShapes: View {
    @State private var isPresented = false
    @State private var flashCount = 0

    var body: some View {
        VStack {
            ScrollView { Text("flashes on a change") }
                .scrollIndicatorsFlash(trigger: flashCount)
                .sheet(isPresented: $isPresented) { Text("sheet") }
                .onChange(of: isPresented) { _, newValue in
                    if newValue { flashCount += 1 }
                }
            ScrollView { Text("flashes on appearing") }
                .scrollIndicatorsFlash(onAppear: true)
                .onScrollPhaseChange { _, newPhase, context in
                    if newPhase == .idle, let velocity = context.velocity, velocity.dy == 0 {
                        flashCount += 1
                    }
                }
            List(0..<20, id: \.self) { Text("row \($0)") }
                .scrollBounceBehavior(.always)
        }
    }
}

// MARK: - View spacing by pair (lane BITEMS1)

/// A spacing preference composed as SwiftUI source composes one — the
/// default, with no space asked for on the leading edge — and read off a
/// layout's subviews, as a layout spacing by preference does; and a row of
/// views left to `spacing: nil`.
@MainActor
private func viewSpacingShapes(_ subviews: LayoutSubviews) -> ViewSpacing {
    var spacing = ViewSpacing()
    spacing.formUnion(.zero, edges: .leading)
    if let first = subviews.first, let last = subviews.last {
        _ = first.spacing.distance(to: last.spacing, along: .horizontal)
    }
    _ = HStack(spacing: nil) { Text("a"); Text("b") }
    return spacing.union(ViewSpacing(), edges: [.top, .bottom])
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
            // Environment-like: either order with `.draggable`, and around a
            // scroll view of draggable text as around a list of it.
            Text("drag me").textSelection(.enabled).draggable("drag me")
            Text("drag me").draggable("drag me").textSelection(.enabled)
            ScrollView {
                ForEach(recipients) { recipient in Text(recipient.name).draggable(recipient.name) }
            }
            .textSelection(.enabled)
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
                    ToolbarItem(id: "share") {
                        ControlGroup {
                            Button("Share") {}
                            Button("Collaborate") {}
                                .toolbarItemHidden(!editing)
                            Button("Mail") {}.toolbarItemHidden()
                        }
                    }
                }
            Text("more")
                .toolbar {
                    Button("Refresh") {}
                    Button("Filter") {}
                }
                .toolbarVisibility(.hidden, for: .windowToolbar)
                .toolbarVisibility(.visible, for: .windowToolbar, .bottomBar)
                .toolbarVisibility(.hidden)
                .toolbarBackground(.blue, for: .windowToolbar)
                .toolbarBackground(.ultraThinMaterial)
                .toolbarBackground(
                    LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing),
                    for: .windowToolbar, .bottomBar)
                .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
                .toolbarBackgroundVisibility(.visible)
                .toolbarRole(.editor)
                .toolbarRole(.automatic)
                .toolbarTitleMenu {
                    Button("Rename") {}
                }
                .toolbar {
                    ToolbarTitleMenu {
                        Button("Duplicate") {}
                        Button("Print") {}
                    }
                    ToolbarTitleMenu()
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Bold") {}
                        Button("Italic") {}
                    } label: {
                        Label("Format", systemImage: "textformat")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("Done") {}
                    }
                    ToolbarItem { Image(systemName: "person.crop.circle") }
                        .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .accessoryBar(id: "com.example.favorites")) { Text("Favorites") }
                }
                .toolbarVisibility(.hidden, for: .accessoryBar(id: "com.example.favorites"))
                .toolbarBackground(.blue, for: .accessoryBar(id: 7))
            TabView {
                Tab("Inbox", systemImage: "tray") { Text("inbox") }
            }
            .tabViewStyle(.sidebarAdaptable)
            .contentToolbar(for: .tabViewSidebar) {
                Button("New Mailbox", systemImage: "plus") {}
            }
            TabView {
                Tab("Home", systemImage: "house") { Text("home") }
            }
            .tabViewStyle(.sidebarAdaptable)
            .contentToolbar(for: .tabViewSidebar) {
                ToolbarItem(placement: .automatic) { Button("Disconnect") {} }
                ToolbarItem(placement: .bottomBar) { Text("Account") }
            }
            LabelStyleReader()
        }
    }
}

/// A customizable toolbar as SwiftUI's documentation writes one: identified
/// items, each customization behaviour, a default customization and its
/// option, a hidden item, an item of a control group hidden within it, a
/// spacer, a title menu, and a conditional item.
@MainActor
private struct CustomizableToolbarShapes: View {
    @State private var showDownloads = false
    @State private var inCollaboration = false

    var body: some View {
        Text("browser")
            .toolbar(id: "browserToolbar") {
                ToolbarItem(id: "new") { Button("New") {} }
                    .customizationBehavior(.disabled)
                ToolbarItem(id: "reorder") { Button("Reorder") {} }
                    .customizationBehavior(.reorderable)
                ToolbarItem(id: "downloads") { Button("Downloads") {} }
                    .hidden(!showDownloads)
                ToolbarItem(id: "extra") { Button("Extra") {} }
                    .defaultCustomization(.hidden)
                ToolbarItem(id: "always") { Button("Always") {} }
                    .defaultCustomization(options: .alwaysAvailable)
                ToolbarItem(id: "share") {
                    ControlGroup {
                        Button("Share") {}
                        Button("Collaborate") {}.toolbarItemHidden(!inCollaboration)
                    }
                }
                .customizationBehavior(.default)
                ToolbarSpacer()
                ToolbarTitleMenu { Button("Rename") {} }
                if showDownloads {
                    ToolbarItem(id: "clear") { Button("Clear") {} }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
            .toolbar(id: "options") {
                ToolbarItem(id: "raw", placement: .primaryAction) { Text("raw") }
                    .defaultCustomization(.visible, options: ToolbarCustomizationOptions(rawValue: 1))
            }
            .toolbar(id: "grouped") {
                Group {
                    ToolbarItem(id: "cut") { Button("Cut") {} }
                    ToolbarItem(id: "copy") { Button("Copy") {} }
                }
                .defaultCustomization(.hidden)
            }
            .toolbar {
                Group {
                    ToolbarItem(placement: .navigation) { Button("Back") {} }
                    ToolbarItem(placement: .primaryAction) { Button("Next") {} }
                }
            }
    }
}

/// A view reading the window's toolbar label style.
@MainActor
private struct LabelStyleReader: View {
    @Environment(\.toolbarLabelStyle) private var style

    var body: some View {
        Text(style == .titleOnly || style == .automatic || style == nil ? "title" : "icon")
    }
}

/// The window toolbar styles, set on a scene as SwiftUI's documentation sets
/// them, and the toolbar label style, fixed and from `@AppStorage`.
@MainActor
private struct ToolbarStyleScenes: Scene {
    @AppStorage("ToolbarLabelStyle") private var labelStyle: ToolbarLabelStyle = .iconOnly

    var body: some Scene {
        WindowGroup { Text("notes") }
            .windowToolbarLabelStyle(fixed: .iconOnly)
            .windowToolbarLabelStyle(fixed: .titleAndIcon)
            .windowToolbarLabelStyle($labelStyle)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .windowToolbarStyle(.unified)
            .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: true))
            .windowToolbarStyle(.expanded)
            .windowToolbarStyle(.automatic)
    }
}
// MARK: - Scroll visibility (lane D5G)

/// SwiftUI's own example for `onScrollVisibilityChange`, and the default
/// threshold.
@MainActor
private struct ScrollVisibilityShapes: View {
    @State private var playing = false

    var body: some View {
        ScrollView {
            VStack {
                Group {
                    Text("video")
                }
                .onScrollVisibilityChange(threshold: 0.2) { isVisible in
                    playing = isVisible
                }
                Text("row")
                    .onScrollVisibilityChange { playing = $0 }
            }
        }
    }
}

// MARK: - Coordinate spaces (lane D5G)

/// SwiftUI's own example for `coordinateSpace(_:)` — a drag located in a named
/// space — and the readers SwiftUI code writes against named spaces and the
/// scroll view's.
@MainActor
private struct CoordinateSpaceShapes: View {
    @State private var location = CellPoint(x: 0, y: 0)
    @State private var offset = 0

    var body: some View {
        VStack {
            Text("Location: \(location.x), \(location.y)")
                .gesture(
                    DragGesture(coordinateSpace: .named("stack"))
                        .onChanged { info in location = info.location })
            ScrollView {
                VStack {
                    GeometryReader { proxy in
                        let minY = proxy.frame(in: .named("scroll")).minY
                        let viewport = proxy.frame(in: .scrollView).minY
                        let vertical = proxy.frame(in: .scrollView(axis: .vertical))
                        let bounds: CellRect? = proxy.bounds(of: .scrollView)
                        let named: CellRect? = proxy.bounds(of: .named("scroll"))
                        Text("\(minY) \(viewport) \(vertical.origin.y) \(bounds?.size.height ?? 0) \(named?.minX ?? 0)")
                    }
                    Text("row")
                        .onGeometryChange(for: Int.self) { proxy in
                            proxy.frame(in: .scrollView).minY
                        } action: { newValue in
                            offset = newValue
                        }
                }
            }
            .coordinateSpace(.named("scroll"))
            Text("tap")
                .onTapGesture(coordinateSpace: .named("stack")) { location = $0 }
        }
        .coordinateSpace(.named("stack"))
        .coordinateSpace(NamedCoordinateSpace.named("other"))
    }
}

private func coordinateSpaceValues() -> Bool {
    let named: CoordinateSpace = .named("stack")
    let resolved = NamedCoordinateSpace.scrollView.coordinateSpace
    return named != resolved && CoordinateSpace.global.isGlobal
}

// MARK: - Anchors (lane D5G)

private struct SelectionBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CellRect>? { nil }
    static func reduce(value: inout Anchor<CellRect>?, nextValue: () -> Anchor<CellRect>?) {
        value = value ?? nextValue()
    }
}

private struct RowBoundsKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CellRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CellRect>], nextValue: () -> [Int: Anchor<CellRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The shapes SwiftUI code writes with anchors: a highlight following the
/// selected row, drawn by a reader in a preference layer, and a background
/// sized to one view's bounds.
@MainActor
private struct AnchorShapes: View {
    @State private var selected = 0

    var body: some View {
        VStack {
            ForEach(0..<3, id: \.self) { index in
                Text("Row \(index)")
                    .anchorPreference(key: RowBoundsKey.self, value: .bounds) { [index: $0] }
            }
            Text("Badge")
                .anchorPreference(key: SelectionBoundsKey.self, value: .bounds) { $0 }
                .transformAnchorPreference(key: RowBoundsKey.self, value: .bounds) { value, anchor in
                    value[99] = anchor
                }
        }
        .overlayPreferenceValue(RowBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if let anchor = anchors[selected] {
                    let rect = proxy[anchor]
                    Text("^").offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .backgroundPreferenceValue(SelectionBoundsKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    Color.blue.frame(width: proxy[anchor].width, height: proxy[anchor].height)
                }
            }
        }
    }
}

private func anchorSources() -> [Anchor<CellPoint>.Source] {
    [
        .center, .topLeading, .top, .topTrailing, .leading, .trailing, .bottomLeading, .bottom,
        .bottomTrailing, .unitPoint(UnitPoint(x: 0.25, y: 0.75)), .point(CellPoint(x: 1, y: 2)),
    ]
}

private func compositeAnchorSources() -> (Anchor<[CellRect]>.Source, Anchor<CellRect?>.Source) {
    (
        Anchor<[CellRect]>.Source([.bounds, .rect(CellRect(x: 0, y: 0, width: 2, height: 1))]),
        Anchor<CellRect?>.Source(Anchor<CellRect>.Source.bounds)
    )
}

/// A popover attached to part of the view that presents it.
@MainActor
private struct PopoverRectAttachment: View {
    @State private var showing = false

    var body: some View {
        Text("Details")
            .popover(
                isPresented: $showing,
                attachmentAnchor: .rect(.rect(CellRect(x: 0, y: 0, width: 3, height: 1))),
                arrowEdge: .bottom
            ) {
                Text("Ganymede")
            }
            .popover(isPresented: $showing, attachmentAnchor: .rect(.bounds)) { Text("Callisto") }
    }
}

// MARK: - Scroll transitions (lane D5G)

/// SwiftUI's shapes for `scrollTransition`: a fade and slide as rows come in,
/// each edge configured on its own, and the configuration spellings.
@MainActor
private struct ScrollTransitionShapes: View {
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(0..<20, id: \.self) { index in
                    Text("Row \(index)")
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.3)
                                .offset(x: Int(phase.value * 4))
                        }
                    Text("Edge \(index)")
                        .scrollTransition(
                            topLeading: .interactive(timingCurve: .easeIn),
                            bottomTrailing: .animated(.spring).threshold(.visible(0.9)),
                            axis: .vertical
                        ) { content, phase in
                            content.brightness(phase.value * 0.2)
                        }
                    Text("Animated \(index)")
                        .scrollTransition(.animated.threshold(.centered.inset(by: 2))) { content, phase in
                            content.grayscale(phase.isIdentity ? 0 : 1)
                        }
                }
            }
        }
    }
}

private func scrollTransitionConfigurations() -> [ScrollTransitionConfiguration] {
    [
        .identity, .interactive, .animated,
        .interactive.animation(.easeOut).threshold(.hidden.interpolated(towards: .visible, amount: 0.5)),
    ]
}

// MARK: - ColorPicker, from a module of its own

/// SwiftUI's own `ColorPicker` example, once more with `supportsOpacity`
/// spelled out, and the two other initializers TUIkit has for a `Color`
/// selection: a `String` title and a label view. Since module split step B4
/// the type is TUIkitColorPicker's, which the umbrella re-exports (and
/// TUIkitCurveEditors), so this is SwiftUI source reaching it as an app does.
@MainActor
private struct FormattingControls: View {
    @State private var bgColor =
        Color(.sRGB, red: 0.98, green: 0.9, blue: 0.2)

    var body: some View {
        VStack {
            ColorPicker("Alignment Guides", selection: $bgColor)
            ColorPicker("Opaque", selection: $bgColor, supportsOpacity: false)
            ColorPicker(String("Computed"), selection: $bgColor)
            ColorPicker(selection: $bgColor) { Text("Built") }
        }
    }
}

// MARK: - Navigation and presentation, from a module of their own

/// A park, as SwiftUI's `NavigationStack` documentation names its data.
private struct CorpusPark: Hashable, Identifiable {
    let id: Int
    let name: String
}

/// SwiftUI's own `NavigationStack` examples: a stack of values pushed by
/// `NavigationLink(_:value:)`, its path bound as an array and as a
/// `NavigationPath`. Since module split step B5 these are TUIkitNavigation's,
/// which the umbrella re-exports (only the umbrella since step C1;
/// TUIkitColorPicker did too from B5 until then), so this is SwiftUI source
/// reaching that module as an app does: through `import TUIkit`.
@MainActor
private struct ParkStack: View {
    let parks: [CorpusPark]
    @State private var presentedParks: [CorpusPark] = []
    @State private var path = NavigationPath()

    var body: some View {
        VStack {
            NavigationStack(path: $presentedParks) {
                List(parks) { park in
                    NavigationLink(park.name, value: park)
                }
                .navigationDestination(for: CorpusPark.self) { park in
                    Text(park.name)
                }
            }
            NavigationStack(path: $path) {
                Button("Show Yosemite") { path.append(CorpusPark(id: 1, name: "Yosemite")) }
                    .navigationDestination(for: CorpusPark.self) { park in Text(park.name) }
            }
        }
    }

    func showParks() {
        presentedParks = [CorpusPark(id: 1, name: "Yosemite"), CorpusPark(id: 2, name: "Sequoia")]
    }
}

/// SwiftUI's own three-column `NavigationSplitView` example, with its column
/// visibility bound, from the same module.
@MainActor
private struct DepartmentSplit: View {
    let departments: [CorpusPark]
    @State private var departmentId: CorpusPark.ID?  // Single selection.
    @State private var employeeIds: Set<CorpusPark.ID> = []  // Multiple selection.
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(departments, selection: $departmentId) { department in
                Text(department.name)
            }
        } content: {
            List(departments, selection: $employeeIds) { employee in
                Text(employee.name)
            }
        } detail: {
            Text("Select a department")
        }
    }
}

/// SwiftUI's own `confirmationDialog` example. The presentations are
/// TUIkitPresentation's since module split step C1 (they compiled into
/// TUIkitNavigation from step B5 until then), which the umbrella re-exports,
/// and so does TUIkitColorPicker.
@MainActor
private struct ConfirmEraseItems: View {
    @State private var isShowingDialog = false

    var body: some View {
        Button("Empty Trash") {
            isShowingDialog = true
        }
        .confirmationDialog(
            "Permanently erase the items in the Trash?",
            isPresented: $isShowingDialog
        ) {
            Button("Empty Trash", role: .destructive) {
                // Handle empty trash action.
            }
        }
    }
}

// MARK: - Lists, tables, tabs and grids, each from a module of its own

/// SwiftUI's own sectioned `List` example, with single selection, under a
/// `NavigationStack` where the documentation's has the deprecated
/// `NavigationView`, and the header as a view builder. Since module split step
/// B6 `List` is TUIkitLists', which the umbrella re-exports, since step C2
/// `Table` is TUIkitTables', which the umbrella alone re-exports, since step C3
/// `TabView` is TUIkitTabs', which the umbrella re-exports (and so does
/// TUIkitColorPicker, which the umbrella re-exports too), and since step C4
/// `Grid` is TUIkitGrid's, which the umbrella alone re-exports; all three were
/// TUIkitLists' from B6 until their peels, and the first two re-export it. So
/// this, the grid below, and the `Table`, `OutlineGroup`, `LazyVGrid` and
/// `TabView` snippets earlier in this file are SwiftUI source reaching those
/// modules as an app does: through `import TUIkit`.
@MainActor
private struct OceanRegionsList: View {
    struct Sea: Hashable, Identifiable {
        let name: String
        let id = UUID()
    }

    struct OceanRegion: Identifiable {
        let name: String
        let seas: [Sea]
        let id = UUID()
    }

    private let oceanRegions: [OceanRegion] = [
        OceanRegion(name: "Pacific", seas: [Sea(name: "Coral"), Sea(name: "South China")]),
        OceanRegion(name: "Arctic", seas: [Sea(name: "Greenland")]),
    ]

    @State private var singleSelection: UUID?

    var body: some View {
        NavigationStack {
            List(selection: $singleSelection) {
                ForEach(oceanRegions) { region in
                    Section {
                        ForEach(region.seas) { sea in
                            Text(sea.name)
                        }
                    } header: {
                        Text("Major \(region.name) Ocean Seas")
                    }
                }
            }
            .navigationTitle("Oceans and Seas")
        }
    }
}

/// SwiftUI's own `Grid` example, with the `Divider` between its rows that the
/// documentation's second example adds, from the same module.
@MainActor
private struct HelloWorldGrid: View {
    var body: some View {
        Grid {
            GridRow {
                Text("Hello")
                Image(systemName: "globe")
            }
            Divider()
            GridRow {
                Image(systemName: "hand.wave")
                Text("World")
            }
        }
    }
}

// MARK: - Menus, help and transitions, from modules of their own

/// SwiftUI's own `Menu` examples: three buttons and a submenu under a title,
/// and a menu whose label is a view builder. Since module split step B5b
/// `Menu` is TUIkitMenus', `help(_:)` TUIkitChrome's and `transition(_:)`
/// TUIkitEffects': the umbrella re-exports each (and TUIkitApp and
/// TUIkitPresentation re-export TUIkitChrome too), so these three snippets, and
/// the `.contextMenu`, `.toolbar` and `.scrollTransition` ones earlier in this
/// file, are SwiftUI source reaching those modules as an app does: through
/// `import TUIkit`.
@MainActor
private struct ActionsMenu: View {
    func duplicate() {}
    func rename() {}
    func delete() {}
    func copy() {}
    func copyFormatted() {}
    func copyPath() {}
    func openInPreview() {}
    func saveAsPDF() {}

    var body: some View {
        VStack {
            Menu("Actions") {
                Button("Duplicate", action: duplicate)
                Button("Rename", action: rename)
                Button("Delete…", action: delete)
                Menu("Copy") {
                    Button("Copy", action: copy)
                    Button("Copy Formatted", action: copyFormatted)
                    Button("Copy Library Path", action: copyPath)
                }
            }
            Menu {
                Button("Open in Preview", action: openInPreview)
                Button("Save as PDF", action: saveAsPDF)
            } label: {
                Label("PDF", systemImage: "doc.fill")
            }
        }
    }
}

/// SwiftUI's own `help(_:)` example: a help tag on a compose button.
@MainActor
private struct ComposeButton: View {
    func composeMessage() {}

    var body: some View {
        Button(action: composeMessage) {
            Image(systemName: "square.and.pencil")
        }
        .help("Compose a new message")
    }
}

/// Help on views that cannot take the focus, in each of SwiftUI's three forms:
/// a localized key, a `Text`, and a string made at run time.
@MainActor
private struct CoverageSummary: View {
    let percent: Int
    let lastRun: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("Coverage").help("Lines the tests ran at least once")
            Text("\(percent)%").help(Text("Measured on the last run"))
            Image(systemName: "checkmark.circle").help(lastRun)
        }
    }
}

/// SwiftUI's own `transition(_:)` example: a view that slides in and out
/// as a button toggles it inside `withAnimation`.
@MainActor
private struct SlidingDetail: View {
    @State private var isActive = false

    var body: some View {
        VStack {
            if isActive {
                Text("Detail")
                    .transition(.slide)
            }
            Button("Toggle") {
                withAnimation {
                    isActive.toggle()
                }
            }
        }
    }
}

// MARK: - Bitmaps, from a module of their own

/// SwiftUI's own `AsyncImage` examples: an icon from a server in a fixed frame,
/// the same made resizable under a `ProgressView` placeholder, and a phase
/// closure that shows a colour for the error and for the wait. Since module
/// split step B5c `AsyncImage`, `Image(_:bundle:)` and the image options are
/// TUIkitBitmaps', which only the umbrella re-exports, so these, and the
/// bitmap snippets earlier in this file, are SwiftUI source reaching it as an
/// app does: through `import TUIkit`. `resizable()` and `aspectRatio` stay
/// TUIkitFoundation's.
@MainActor
private struct ServerIcons: View {
    var body: some View {
        VStack {
            AsyncImage(url: URL(string: "https://example.com/icon.png"))
                .frame(width: 200, height: 200)
            AsyncImage(url: URL(string: "https://example.com/icon.png")) { image in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 50, height: 50)
            AsyncImage(url: URL(string: "https://example.com/icon.png")) { phase in
                if let image = phase.image {
                    image // Displays the loaded image.
                } else if phase.error != nil {
                    Color.red // Indicates an error.
                } else {
                    Color.blue // Acts as a placeholder.
                }
            }
            Image("Landscape_4", bundle: nil)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - Text inputs, pickers, forms, search and numeric controls, from a module of their own

/// SwiftUI's own `Form` example, its notification and profile settings, with a
/// text field, a stepper and a slider added to its first section and each
/// header as a view builder (the documentation's `Section(header:)` is
/// deprecated), and its own `searchable(text:)` example. Since module split step B7 `TextField`
/// is TUIkitTextInput's, which the umbrella re-exports (and TUIkitColorPicker
/// and TUIkitSearch, which the umbrella re-exports too), `Picker` is
/// TUIkitPickers' since step C8, which the same three re-export, `Stepper`
/// and `Slider` TUIkitNumericControls' since step C7, which the umbrella and
/// TUIkitColorPicker re-export, `Form` is TUIkitForms' since step C6 and `.searchable`
/// TUIkitSearch's since step C5, which only the umbrella re-exports, so this,
/// and the text input, picker, form, search and numeric snippets earlier in
/// this file, are SwiftUI source reaching those modules as an app does:
/// through `import TUIkit`.
@MainActor
private struct NotificationSettingsForm: View {
    enum NotifyMeAboutType {
        case directMessages
        case mentions
        case anything
    }

    enum ProfileImageSize {
        case large
        case medium
        case small
    }

    @State private var notifyMeAbout: NotifyMeAboutType = .directMessages
    @State private var playNotificationSounds = true
    @State private var sendReadReceipts = false
    @State private var profileImageSize: ProfileImageSize = .medium
    @State private var displayName = ""
    @State private var reminderCount = 3
    @State private var volume = 0.5
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Notify Me About", selection: $notifyMeAbout) {
                        Text("Direct Messages").tag(NotifyMeAboutType.directMessages)
                        Text("Mentions").tag(NotifyMeAboutType.mentions)
                        Text("Anything").tag(NotifyMeAboutType.anything)
                    }
                    Toggle("Play notification sounds", isOn: $playNotificationSounds)
                    Toggle("Send read receipts", isOn: $sendReadReceipts)
                    TextField("Display name", text: $displayName)
                    Stepper("Reminders: \(reminderCount)", value: $reminderCount, in: 0...10)
                    Slider(value: $volume, in: 0...1) { Text("Volume") }
                } header: {
                    Text("Notifications")
                }
                Section {
                    Picker("Profile Image Size", selection: $profileImageSize) {
                        Text("Large").tag(ProfileImageSize.large)
                        Text("Medium").tag(ProfileImageSize.medium)
                        Text("Small").tag(ProfileImageSize.small)
                    }
                    Button("Clear Image Cache") {}
                } header: {
                    Text("User Profiles")
                }
            }
            .navigationTitle("Searching for \(searchText)")
        }
        .searchable(text: $searchText)
    }
}

/// SwiftUI's own `VisualEffect` example: an offset following the view's global
/// position, which draws its offset now that the proxy answers `.global`.
@MainActor
private struct GlobalVisualEffect: View {
    var body: some View {
        Text("ContentRow")
            .visualEffect { content, geometryProxy in
                content.offset(x: geometryProxy.frame(in: .global).origin.y)
            }
    }
}

/// Matched geometry as SwiftUI code writes it: a bar following the selected
/// tab (`isSource: false`, anchored under it), and a view carried between two
/// places by an animated change of which one is shown.
@MainActor
private struct MatchedGeometryTabs: View {
    @Namespace private var animation
    @State private var selected = 0
    @State private var isExpanded = false

    var body: some View {
        VStack {
            HStack {
                ForEach(0..<3, id: \.self) { index in
                    Text("Tab \(index)")
                        .matchedGeometryEffect(id: index, in: animation, anchor: .bottom)
                        .onTapGesture {
                            withAnimation(.spring()) { selected = index }
                        }
                }
            }
            Color.blue
                .frame(height: 1)
                .matchedGeometryEffect(id: selected, in: animation, anchor: .top, isSource: false)
            if isExpanded {
                Text("Detail")
                    .matchedGeometryEffect(id: "card", in: animation, properties: [.position, .size])
            } else {
                Text("Card")
                    .matchedGeometryEffect(id: "card", in: animation, properties: .frame, anchor: .center, isSource: true)
            }
            Button("Toggle") { withAnimation { isExpanded.toggle() } }
        }
    }
}

/// The zoom navigation transition as iOS code writes it: each row the source
/// of the screen its link pushes, configured with a background.
@MainActor
private struct ZoomFromRows: View {
    @Namespace private var namespace
    private let colors = ["Red", "Green", "Blue"]

    var body: some View {
        NavigationStack {
            List(colors, id: \.self) { color in
                NavigationLink {
                    Text(color)
                        .navigationTransition(.zoom(sourceID: color, in: namespace))
                } label: {
                    Text(color)
                }
                .matchedTransitionSource(id: color, in: namespace) { source in
                    source
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8, y: 4)
                }
            }
        }
    }
}

// MARK: - A property wrapper that keeps what update() derives

/// The commonest non-trivial `DynamicProperty`: it reads the environment and
/// keeps what it derives in a stored value of its own, in `update()`. SwiftUI
/// writes that value back before `body` reads it, and TUIkit does too
/// (decisions B4).
@propertyWrapper
private struct CorpusLocaleName: DynamicProperty {
    @Environment(\.locale) private var locale
    private var cached = ""

    var wrappedValue: String { cached }

    mutating func update() {
        cached = locale.identifier.uppercased()
    }
}

@MainActor
private struct LocaleBadge: View {
    @CorpusLocaleName private var localeName: String

    var body: some View {
        Text(localeName)
    }
}

// MARK: - A view that is an enum, its cases holding properties

/// A `DynamicProperty` keeping a counter of its own in `@State`.
private struct CorpusTally: DynamicProperty {
    @State private var count = 0

    var binding: Binding<Int> { $count }
}

/// SwiftUI gives each case's properties their own state, reset when another
/// case replaces it, and binds a property beside other values in one case
/// (lane SKEY, measured on macOS 15).
@MainActor
private enum CorpusScreen: View {
    case list(CorpusTally)
    case detail(CorpusTally, title: String)

    var body: some View {
        switch self {
        case .list(let tally):
            Stepper("Rows", value: tally.binding)
        case let .detail(tally, title):
            Stepper(title, value: tally.binding)
        }
    }
}

// MARK: - Where SwiftUI finds a view's properties (lane DYNVFIX)

/// An app property that is an enum: what `update()` changes in its payload is
/// written back before `body` reads it, as SwiftUI writes it back.
private struct CorpusElapsed: DynamicProperty {
    var ticks = 0

    mutating func update() {
        ticks += 1
    }
}

private enum CorpusStopwatch: DynamicProperty {
    case running(CorpusElapsed)
    case stopped
}

@MainActor
private struct CorpusLap: View {
    var watch: CorpusStopwatch

    var body: some View {
        if case .running(let elapsed) = watch {
            Text("\(elapsed.ticks)")
        } else {
            Text("stopped")
        }
    }
}

/// A view whose custom mirror leaves its `@State` out keeps it all the same.
@MainActor
private struct CorpusLogin: View, CustomReflectable {
    let account: String
    @State private var password = ""

    nonisolated var customMirror: Mirror { Mirror(self, children: ["account": account]) }

    var body: some View {
        SecureField("Password", text: $password)
    }
}

/// A view holding a back-reference `unowned`, which `body` never reads.
private final class CorpusConnection {
    func retry() {}
}

@MainActor
private struct CorpusRetryBar: View {
    unowned let connection: CorpusConnection
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button("Retry") { connection.retry() }.disabled(!enabled)
    }
}

/// One view value placed twice: two tallies.
@MainActor
private struct CorpusTallyButton: View {
    @State private var taps = 0

    var body: some View {
        Button("Tally \(taps)") { taps += 1 }
    }
}

@MainActor
private struct CorpusToolbar: View {
    var body: some View {
        let tally = CorpusTallyButton()
        HStack {
            tally
            Spacer()
            tally
        }
    }
}

/// A modifier stored in a view and applied: its properties update once.
private struct CorpusDimmed: ViewModifier {
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content.opacity(enabled ? 1 : 0.5)
    }
}

@MainActor
private struct CorpusInbox: View {
    let dimming = CorpusDimmed()

    var body: some View {
        Text("Inbox")
            .modifier(dimming)
            .modifier(CorpusDimmed().transaction { $0.animation = nil })
    }
}

/// A class property: its own `update()` runs before each holder's body.
private final class CorpusCoordinator: DynamicProperty {
    weak var parent: CorpusCoordinator?
    var detail: CorpusCoordinator?
}

@MainActor
private struct CorpusFormView: View {
    let coordinator: CorpusCoordinator

    var body: some View {
        Text("Form")
    }
}


// MARK: - Class properties held by several views (lane DYNVCLAIM)

/// A class property holding a `@State` and an `@Environment`, shown by a row
/// and by a detail view that changes it: SwiftUI installs neither inside a
/// class, TUIkit installs both as the object's.
private final class CorpusDocument: DynamicProperty {
    @State var expanded = false
    @Environment(\.isEnabled) var enabled
}

@MainActor
private struct CorpusDocumentRow: View {
    let document: CorpusDocument

    var body: some View {
        Text(document.expanded ? "Document, expanded" : "Document")
    }
}

@MainActor
private struct CorpusDocumentDetail: View {
    let document: CorpusDocument

    var body: some View {
        Toggle("Expanded", isOn: document.$expanded).disabled(!document.enabled)
    }
}

/// An object made with each value of the view holding it, turned by a
/// button whose action holds it.
private final class CorpusPager: DynamicProperty {
    @State var page = 0
}

@MainActor
private struct CorpusPagerView: View {
    let pager = CorpusPager()

    var body: some View {
        Button("Page \(pager.page)") { pager.page += 1 }
    }
}

// MARK: - Shapes (lane W1)

/// A shape of the app's own, written as SwiftUI's documentation writes one:
/// computed from the rectangle it is given, so it keeps its proportions in
/// TUIkit's square units.
private struct CorpusTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// An insettable shape of the app's own, so `strokeBorder` reaches it.
private struct CorpusInsetDiamond: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.addLines([
            CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY),
            CGPoint(x: frame.midX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.midY),
        ])
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Self {
        Self(inset: inset + amount)
    }
}

/// An animatable shape: its data is `CGFloat`, as SwiftUI's examples write it.
private struct CorpusWedge: Shape {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(fraction)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

@MainActor
private struct CorpusShapes: View {
    @State private var progress: CGFloat = 0.25

    var body: some View {
        VStack {
            Rectangle()
            Rectangle().fill(.red)
            Circle().fill(.blue, style: FillStyle(eoFill: true, antialiased: false))
            Circle().stroke(lineWidth: 2)
            Circle().stroke(.green, lineWidth: 1)
            Circle().stroke(.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0, 4]))
            Circle().strokeBorder(.orange, lineWidth: 1)
            Circle().strokeBorder(lineWidth: 2)
            Ellipse().fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
            Capsule(style: .circular).fill(.purple)
            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.gray)
            RoundedRectangle(cornerSize: CGSize(width: 4, height: 2)).fill(.mint)
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomTrailingRadius: 3).fill(.teal)
            UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 2), style: .circular).stroke(.cyan)
            ContainerRelativeShape().fill(.yellow)
            CorpusTriangle().fill(.orange)
            CorpusInsetDiamond().strokeBorder(.white, lineWidth: 1)
            CorpusWedge(fraction: progress).fill(.pink)
            Circle().trim(from: 0, to: progress).stroke(.blue, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            Rectangle().rotation(.degrees(30)).fill(.red)
            Rectangle().scale(0.5).fill(.red)
            Rectangle().scale(x: 0.5, y: 1, anchor: .leading).fill(.red)
            Rectangle().transform(CGAffineTransform(rotationAngle: 0.5)).fill(.red)
            Rectangle().size(width: 4, height: 2).fill(.red)
            Rectangle().size(CGSize(width: 4, height: 2), anchor: .center).fill(.red)
            AnyShape(Circle()).fill(.red)
            Circle().fill(.yellow).stroke(.red, lineWidth: 1)
            Capsule().fill(.yellow).strokeBorder(.red, lineWidth: 1)
            Path { $0.addEllipse(in: CGRect(x: 0, y: 0, width: 10, height: 10)) }.fill(.green)
        }
    }

    /// The leading-dot spellings, where a concrete shape is expected.
    var shapes: [AnyShape] {
        [
            AnyShape(.rect), AnyShape(.circle), AnyShape(.capsule), AnyShape(.ellipse), AnyShape(.containerRelative),
            AnyShape(.rect(cornerRadius: 2)), AnyShape(.rect(cornerSize: CGSize(width: 2, height: 1))),
            AnyShape(.rect(cornerRadii: RectangleCornerRadii(topLeading: 2))),
            AnyShape(.rect(topLeadingRadius: 2, bottomTrailingRadius: 2)), AnyShape(.capsule(style: .circular)),
        ]
    }

    /// A shape's adapters keep their types, as SwiftUI's do.
    var adapters: (OffsetShape<Circle>, RotatedShape<Rectangle>, ScaledShape<Ellipse>, TransformedShape<Capsule>) {
        (
            Circle().offset(x: 2, y: 1), Rectangle().rotation(.degrees(45)), Ellipse().scale(2),
            Capsule().transform(.identity)
        )
    }

    /// Path's value API.
    func pathArithmetic() -> (CGRect, Bool, Path, String) {
        var path = Path(roundedRect: CGRect(x: 0, y: 0, width: 10, height: 4), cornerRadius: 1)
        path.addRelativeArc(center: .zero, radius: 2, startAngle: .zero, delta: .degrees(90))
        path.addArc(tangent1End: CGPoint(x: 5, y: 0), tangent2End: CGPoint(x: 5, y: 5), radius: 1)
        path.addQuadCurve(to: CGPoint(x: 1, y: 1), control: .zero)
        path.addCurve(to: CGPoint(x: 2, y: 2), control1: .zero, control2: CGPoint(x: 1, y: 2))
        path.forEach { element in
            if case .closeSubpath = element { return }
        }
        let moved = path.applying(CGAffineTransform(translationX: 1, y: 1)).offsetBy(dx: 1, dy: 1)
        return (moved.boundingRect, moved.contains(.zero, eoFill: true), moved.trimmedPath(from: 0, to: 0.5), moved.description)
    }
}

/// Shapes behind, over, clipping and as the hit area, as SwiftUI's
/// documentation writes them.
@MainActor
private struct CorpusShapeModifiers: View {
    let trapezoid = Path { path in
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 9, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 5))
        path.addLine(to: CGPoint(x: 1, y: 5))
    }

    var body: some View {
        VStack {
            Label("Flag", systemImage: "flag.fill").padding().background(.teal, in: trapezoid)
            Text("Tag").padding(.horizontal, 1).background(.purple, in: Capsule())
            Text("Card").background(in: RoundedRectangle(cornerRadius: 2))
            Text("Card").background(.blue, in: RoundedRectangle(cornerRadius: 2), fillStyle: FillStyle(eoFill: true))
            Text("Marked").overlay(.red.opacity(0.3), in: Ellipse())
            Text("Clipped text in a circle").frame(width: 20, height: 10).clipShape(Circle())
            Color.orange.clipShape(.rect(cornerRadius: 3), style: FillStyle(eoFill: false))
            HStack { Text("Row"); Spacer() }.contentShape(Rectangle()).onTapGesture {}
            Text("Row").contentShape(.rect)
            Image(systemName: "circle.fill").contentShape(Circle()).onTapGesture {}
            Text("Card").contentShape(.dragPreview, RoundedRectangle(cornerRadius: 10)).draggable("card")
            Text("Both").contentShape([.interaction, .dragPreview], Capsule(), eoFill: false)
        }
    }
}

/// Container shapes and the shapes that follow them, macOS 26's corner
/// vocabulary included.
@MainActor
private struct CorpusContainerShapes: View {
    var body: some View {
        VStack {
            Text("Inner")
                .padding(1)
                .background(.blue, in: ContainerRelativeShape())
                .padding(1)
                .containerShape(RoundedRectangle(cornerRadius: 3))
            ConcentricRectangle().fill(.red).padding(1).containerShape(.rect(cornerRadius: 3))
            ConcentricRectangle(corners: .concentric(minimum: 1), isUniform: true).stroke(.green)
            ConcentricRectangle(topLeadingCorner: .concentric, topTrailingCorner: 0, bottomLeadingCorner: .fixed(2))
                .fill(.orange)
            ConcentricRectangle(uniformTopCorners: .concentric, uniformBottomCorners: 0).fill(.mint)
            ContainerRelativeShape().strokeBorder(.white, lineWidth: 1).containerShape(Capsule())
        }
    }

    var corners: (RoundedRectangularShapeCorners?, Edge.Corner.Set, CGFloat, AnyShape) {
        (
            RoundedRectangle(cornerRadius: 2).corners(in: CGSize(width: 10, height: 4)), [.top, .bottomLeading],
            RectangleCornerRadii(topLeading: 2)[.topLeading],
            AnyShape(.rect(corners: .concentric, isUniform: false))
        )
    }
}

/// A sheet's corner radius, as SwiftUI's documentation writes it.
@MainActor
private struct CorpusPresentationCornerRadius: View {
    @State private var showSettings = false

    var body: some View {
        Button("View Settings") { showSettings = true }
            .sheet(isPresented: $showSettings) {
                Text("Settings")
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(21)
            }
    }
}

// MARK: - Shadows, in whole cells (lane O6)

/// `shadow(color:radius:x:y:)` as SwiftUI code writes it: the radius alone, a
/// translucent colour with an offset, and a semantic colour. Integer literals
/// are cells here (`.padding(8)`'s unit); a fractional radius does not compile.
@MainActor
private struct CorpusShadowedCards: View {
    var body: some View {
        VStack {
            Text("Card").padding().background(.white).shadow(radius: 4)
            Text("Lifted").shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            Color.blue.shadow(color: .primary, radius: 0, x: 2, y: 2)
        }
    }
}

/// `ShadowStyle`'s two kinds, every argument but the radius defaulted or stated.
private let corpusShadowStyles: [ShadowStyle] = [
    .drop(radius: 2), .drop(color: .black.opacity(0.4), radius: 1, x: 1, y: 2), .inner(radius: 1, y: 1),
]

/// `ShapeStyle.shadow(_:)` as Apple's documentation writes it — on a colour, and
/// the static form on the current style — and where a style goes: a shape, a
/// background, the foreground, the background style.
private struct CorpusShadowedStyles: View {
    var body: some View {
        VStack {
            Rectangle().fill(.red.shadow(.drop(radius: 2, y: 3)))
            Circle().fill(.shadow(.inner(radius: 1, y: 1)))
            Capsule().stroke(.blue.shadow(.drop(color: .black.opacity(0.4), radius: 1, x: 1)), lineWidth: 1)
            Text("Pressed").padding().background(.blue.shadow(.inner(radius: 1, x: 1, y: 1)))
            Text("Raised").foregroundStyle(.white.shadow(.drop(radius: 0, x: 1, y: 1)))
            Text("Well").padding().background().backgroundStyle(.shadow(.inner(radius: 2)))
            Rectangle().fill(.image(Image(.file("tile.png")), sourceRect: CGRect(x: 0, y: 0, width: 0.5, height: 1), scale: 0.5))
            Circle().fill(ImagePaint(image: Image(.file("tile.png")), scale: 2))
            Text("Grain").foregroundStyle(ImagePaint(image: Image(.file("grain.png"))))
        }
    }
}

// MARK: - Commands

/// SwiftUI's command vocabulary as its documentation writes it: a menu of the
/// app's own, additions to and replacements of the standard groups, `if` and
/// `if`/`else`, a `Group` past ten, and commands of the app's own type reading
/// the focused view's value.
@MainActor
private struct CorpusNoteCommands: Commands {
    @FocusedValue(\.corpusNoteTitle) private var noteTitle
    @Environment(\.isEnabled) private var isEnabled

    var body: some Commands {
        CommandMenu("Note") {
            Button("Duplicate \(noteTitle ?? "")") {}
                .keyboardShortcut("d")
                .disabled(noteTitle == nil)
            Divider()
            Section("Danger") {
                Button("Delete", role: .destructive) {}
            }
        }
        CommandMenu(Text("Format")) {
            Toggle("Bold", isOn: .constant(isEnabled))
        }
        CommandGroup(replacing: .newItem) {
            Button("New Note") {}.keyboardShortcut("n")
        }
        CommandGroup(before: .undoRedo) { Button("History") {} }
        CommandGroup(after: .pasteboard) { Button("Paste Plain") {} }
        if isEnabled {
            CommandGroup(after: .help) { Button("Guide") {} }
        } else {
            EmptyCommands()
        }
        Group {
            CommandGroup(after: .appInfo) { Button("Licence") {} }
            CommandGroup(replacing: .appTermination) { Button("Leave") {} }
        }
    }
}

private struct CorpusNoteTitleKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    fileprivate var corpusNoteTitle: String? {
        get { self[CorpusNoteTitleKey.self] }
        set { self[CorpusNoteTitleKey.self] = newValue }
    }
}

/// Every placement SwiftUI names.
@MainActor
private let corpusPlacements: [CommandGroupPlacement] = [
    .appInfo, .appSettings, .systemServices, .appVisibility, .appTermination, .newItem, .saveItem, .importExport,
    .printItem, .undoRedo, .pasteboard, .textEditing, .textFormatting, .toolbar, .sidebar, .windowSize,
    .windowArrangement, .windowList, .singleWindowList, .help,
]

/// The scene modifiers that declare commands, as SwiftUI's docs write them.
@MainActor
private struct CorpusCommandsScene: Scene {
    var body: some Scene {
        WindowGroup { Text("Notes") }
            .commands {
                CorpusNoteCommands()
                CommandMenu("Tools") { Button("Run") {} }
                SidebarCommands()
                InspectorCommands()
                ToolbarCommands()
                TextEditingCommands()
            }
            .commandsRemoved()
            .commandsReplaced {
                CommandGroup(after: .pasteboard) {
                    Section { Button("Show Clipboard") {} }
                }
            }
    }
}

// MARK: - Small parity items (lane PARITYMISC)

/// `DefaultPickerStyle` is the type `.automatic` names, and a spacer's
/// `minLength` reads and sets under SwiftUI's name.
@MainActor
private struct CorpusDefaultPickerStyleAndSpacer: View {
    @State private var choice = 0

    var body: some View {
        var spacer = Spacer(minLength: 2)
        spacer.minLength = spacer.minLength.map { $0 + 1 }
        return HStack {
            Picker("Choice", selection: $choice) {
                Text("One").tag(0)
            }
            .pickerStyle(DefaultPickerStyle())
            spacer
        }
    }
}

/// A selection erased to `AnyHashable`, handed a binding to a concrete
/// `Hashable` value.
@MainActor
private struct CorpusAnyHashableBinding: View {
    @State private var count = 0

    var body: some View {
        let erased: Binding<AnyHashable> = Binding($count)
        return Text("\(erased.wrappedValue.description)")
    }
}

/// An image wrapped as text, interpolated into a key.
@MainActor
private struct CorpusTextOfImage: View {
    var body: some View {
        VStack {
            Text(Image(systemName: "star.fill"))
            Text("\(Text(Image(systemName: "star.fill"))) Favourites")
        }
    }
}

/// A scroll view's stored properties, read and set as SwiftUI code does: the
/// initializer that took `showsIndicators:` is deprecated, the property is not.
@MainActor
private struct CorpusScrollViewProperties: View {
    var body: some View {
        var scroller = ScrollView {
            Text("scrolled")
        }
        scroller.showsIndicators = false
        scroller.axes = [.vertical, .horizontal]
        _ = scroller.content
        return scroller
    }
}

/// Content types as SwiftUI spells them on macOS (`NSTextContentType`).
@MainActor
private struct CorpusTextContentTypes: View {
    @State private var url = ""
    @State private var card = ""
    @State private var notes = ""

    var body: some View {
        VStack {
            TextField("URL", text: $url)
                .textContentType(.URL)
            TextField("Card", text: $card)
                .textContentType(.creditCardNumber)
            TextEditor(text: $notes)
                .textContentType(.fullStreetAddress)
        }
    }
}

// MARK: - Glass (lane GLASS)

/// `glassEffect(_:in:)` as Apple's documentation writes it: the defaults, the
/// clear variant over a dimming layer, a tinted interactive glass in a shape of
/// the caller's, and the identity glass.
@MainActor
private struct CorpusGlassLabels: View {
    var body: some View {
        VStack {
            Label("Flag", systemImage: "flag.fill").padding().glassEffect()
            Label("Flag", systemImage: "flag.fill")
                .padding()
                .glassEffect(.clear)
                .background(.black.opacity(0.3))
            Text("Tinted").padding().glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 2))
            Text("Plain").glassEffect(.identity, in: Circle())
            Text("Default shape").glassEffect(.regular, in: DefaultGlassEffectShape())
        }
    }
}

/// `GlassEffectContainer` and `glassEffectUnion(id:namespace:)` as Apple's
/// documentation writes them: the default spacing, a stated one, and a union
/// keyed by a value of the app's own.
@MainActor
private struct CorpusGlassContainers: View {
    private enum Placement: Hashable, Sendable { case leading, trailing }

    @Namespace private var namespace

    var body: some View {
        VStack {
            GlassEffectContainer {
                HStack {
                    Image(systemName: "pencil").glassEffect()
                    Image(systemName: "note").glassEffect()
                }
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Text("One").padding().glassEffect().glassEffectUnion(id: Placement.leading, namespace: namespace)
                    Text("Two").padding().glassEffect().glassEffectUnion(id: Placement.leading, namespace: namespace)
                    Text("Three").padding().glassEffect().glassEffectUnion(id: nil as Placement?, namespace: namespace)
                }
            }
        }
    }
}

/// `glassEffectID(_:in:)` and `glassEffectTransition(_:)` as Apple's
/// documentation writes them, with every transition spelled.
@MainActor
private struct CorpusGlassTransitions: View {
    var isExpanded: Bool
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .frame(width: 20, height: 20)
                    .glassEffect()
                    .glassEffectID("pencil", in: namespace)
                if isExpanded {
                    Image(systemName: "note")
                        .frame(width: 20, height: 20)
                        .glassEffect()
                        .glassEffectID("note", in: namespace)
                        .glassEffectTransition(.matchedGeometry)
                }
                Text("Fades").glassEffect().glassEffectTransition(.materialize)
                Text("At once").glassEffect().glassEffectTransition(.identity)
            }
        }
    }
}

/// The glass button styles as Apple's documentation writes them.
@MainActor
private struct CorpusGlassButtons: View {
    var body: some View {
        HStack {
            Button("Button") {}.buttonStyle(.glass)
            Button("Button") {}.buttonStyle(.glass(.clear))
            Button("Button") {}.buttonStyle(.glassProminent)
            Button("Button") {}.buttonStyle(GlassButtonStyle(.regular.tint(.purple)))
            Button("Button") {}.buttonStyle(GlassProminentButtonStyle())
        }
    }
}

// MARK: - Several scenes (lane O9)

/// A body of several scenes, one behind an availability check, and a group of
/// scenes, as SwiftUI's `SceneBuilder` documentation writes them.
private struct CorpusSeveralScenesApp: App {
    var body: some Scene {
        WindowGroup { Text("Main") }
        if #available(macOS 14, *) {
            WindowGroup { Text("Later") }
        }
        Group {
            WindowGroup { Text("Grouped") }
            WindowGroup { Text("Also grouped") }
        }
        .environment(\.lineSpacing, 1)
    }
}

/// Windows opened and dismissed by identifier, as `OpenWindowAction`'s and
/// `DismissWindowAction`'s documentation write them.
private struct CorpusWindowsApp: App {
    var body: some Scene {
        WindowGroup { CorpusNewViewerButton() }
        WindowGroup(id: "mail-viewer") { Text("Viewer") }
        WindowGroup("Titled", id: "titled") { Text("Titled") }
        WindowGroup(Text("Text titled")) { Text("Text titled") }
        Window("Auxiliary", id: "auxiliary") { CorpusDismissWindowButton() }
    }
}

@MainActor
private struct CorpusNewViewerButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        Button("Open new mail viewer") {
            openWindow(id: "mail-viewer")
        }
        .disabled(!supportsMultipleWindows)
    }
}

@MainActor
private struct CorpusDismissWindowButton: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button("Close Auxiliary Window") {
            dismissWindow(id: "auxiliary")
        }
        Button("Close") { dismissWindow() }
    }
}

/// A window group that presents data, opened and dismissed by value, as
/// `OpenWindowAction`'s documentation writes it.
private struct CorpusPresentedDataApp: App {
    var body: some Scene {
        WindowGroup { CorpusOpenMessageButton() }
        WindowGroup(for: Int.self) { $messageID in
            Text("Message \(messageID ?? 0)")
        }
        WindowGroup("Drafts", id: "drafts", for: String.self) { $draft in
            Text(draft)
        } defaultValue: {
            "New draft"
        }
    }
}

@MainActor
private struct CorpusOpenMessageButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button("Open message") { openWindow(value: 42) }
        Button("Open draft") { openWindow(id: "drafts", value: "Hello") }
        Button("Close message") { dismissWindow(value: 42) }
        Button("Share") {
            Task { try await openWindow(id: "drafts", sharingBehavior: .requested) }
        }
    }
}

/// A window dismissed whatever it shows, as `DismissBehavior`'s documentation
/// writes it.
@MainActor
private struct CorpusDestructiveDismissButton: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button("Close Auxiliary Window") {
            withTransaction(\.dismissBehavior, .destructive) {
                dismissWindow(id: "auxiliary")
            }
        }
    }
}

/// A window only its own button closes, as `windowDismissBehavior(_:)`'s
/// documentation writes it.
private struct CorpusWelcomeApp: App {
    var body: some Scene {
        Window("Welcome", id: "welcome") {
            CorpusDestructiveDismissButton()
                .windowDismissBehavior(.disabled)
        }
        Window("Tips", id: "tips") {
            Text("Tips")
                .windowDismissBehavior(.enabled)
                .windowDismissBehavior(.automatic)
        }
    }
}

/// A window shown and hidden from the menu bar, as `WindowVisibilityToggle`'s
/// documentation writes it.
private struct CorpusPhotoLibraryApp: App {
    var body: some Scene {
        WindowGroup { Text("Photos") }
            .commands {
                CommandGroup(before: .sidebar) {
                    WindowVisibilityToggle(windowID: "photo-library")
                        .keyboardShortcut("l", modifiers: [.command, .shift])
                }
            }
        Window("Photo Library", id: "photo-library") { Text("Library") }
            .keyboardShortcut("0", modifiers: [.command, .option])
        WindowGroup("Viewer", id: "viewer") { Text("Viewer") }
            .keyboardShortcut(KeyboardShortcut("v", modifiers: [.command, .shift]))
        #if os(macOS)
        Settings { Text("Settings") }
            .keyboardShortcut(nil)
        #endif
    }
}

/// The settings scene and the ways to it, as `OpenSettingsAction`'s and
/// `Settings`' documentation write them.
private struct CorpusSettingsApp: App {
    var body: some Scene {
        WindowGroup { CorpusAdvancedSettingsButton() }
        #if os(macOS)
        Settings {
            Text("Settings")
        }
        #endif
    }
}

@MainActor
private struct CorpusAdvancedSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Advanced Settings…") { openSettings() }
        SettingsLink()
        SettingsLink { Label("Preferences", systemImage: "gearshape") }
    }
}

/// An alert that is a scene, with the scene dialog modifiers, as
/// `AlertScene`'s and `Scene.dialogSeverity(_:)`'s documentation write them.
private struct CorpusAlertSceneApp: App {
    @State private var isShowingDialog = false
    @State private var suppressAlert = false

    var body: some Scene {
        Window("Items", id: "items") {
            Button("Delete items") { isShowingDialog = true }
        }
        AlertScene("Are you sure you want to erase these items?", isPresented: $isShowingDialog) {
            Button("Erase", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .dialogSeverity(.critical)
        .dialogIcon(nil)
        .dialogSuppressionToggle("Don't ask again", isSuppressed: $suppressAlert)
        .dialogSuppressionToggle(isSuppressed: $suppressAlert)
        AlertScene(Text("Login Required"), isPresented: $isShowingDialog, presenting: "name") { name in
            Button(name) {}
        }
    }
}

// MARK: - Pointer styles (decisions O12)

/// `pointerStyle(_:)` as Apple's documentation writes it — an optional style
/// chosen per state — and every style SwiftUI declares but the image one.
@MainActor
private struct CorpusPointerStyles: View {
    enum ToolMode { case selection }
    @State private var toolMode: ToolMode?

    var body: some View {
        VStack {
            Text("Canvas")
                .pointerStyle(toolMode == .selection ? .rectSelection : nil)
                .onModifierKeysChanged { _, modifierKeys in
                    toolMode = modifierKeys.contains(.option) ? .selection : nil
                }
            Divider().pointerStyle(.columnResize)
            Divider().pointerStyle(.columnResize(directions: .trailing))
            Divider().pointerStyle(.rowResize(directions: [.up, .down]))
            Color.clear.pointerStyle(.frameResize(position: .bottomTrailing))
            Color.clear.pointerStyle(.frameResize(position: .top, directions: .outward))
            Text("Pan").pointerStyle(.grabIdle)
            Text("Panning").pointerStyle(.grabActive)
            Text("Text").pointerStyle(.horizontalText)
            Text("Vertical").pointerStyle(.verticalText)
            Link("Docs", destination: URL(string: "https://example.com")!).pointerStyle(.link)
            Text("Zoom").pointerStyle(.zoomIn).pointerStyle(.zoomOut).pointerStyle(.default)
        }
    }
}

// MARK: - File panels (lane O10)

/// The three importers as SwiftUI's documentation writes them: the template
/// directory picker of `fileImporter(isPresented:allowedContentTypes:onCompletion:)`
/// (its security-scoped access included), the PDF combiner of the multiple
/// form, and the `onCancellation:` form with its trailing closures.
@MainActor
private struct CorpusFileImporters: View {
    @State private var showFileImporter = false
    var onTemplatesDirectoryPicked: (URL) -> Void
    var handlePickedPDF: (URL) -> Void

    var body: some View {
        VStack {
            Button {
                showFileImporter = true
            } label: {
                Label("Choose templates directory", systemImage: "folder.circle")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.directory]
            ) { result in
                switch result {
                case .success(let directory):
                    let gotAccess = directory.startAccessingSecurityScopedResource()
                    if !gotAccess { return }
                    onTemplatesDirectoryPicked(directory)
                    directory.stopAccessingSecurityScopedResource()
                case .failure(let error):
                    print(error)
                }
            }
            Button("Choose PDFs to combine") { showFileImporter = true }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let files) = result { files.forEach(handlePickedPDF) }
                }
            Button("Import notes") { showFileImporter = true }
                .fileImporter(
                    isPresented: $showFileImporter, allowedContentTypes: [.plainText, .json],
                    allowsMultipleSelection: false
                ) { result in
                    _ = result
                } onCancellation: {
                    print("cancelled")
                }
        }
    }
}

/// The `fileDialog` customizations as Apple's documentation writes them,
/// outside the presenting modifier, every form of each.
@MainActor
private struct CorpusFileDialogCustomizations: View {
    @State private var importing = false
    var documents: URL

    var body: some View {
        Button("Combine") { importing = true }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { _ in }
            .fileDialogMessage("Choose the PDFs to combine")
            .fileDialogMessage(Text("Choose"))
            .fileDialogMessage(String("Choose"))
            .fileDialogConfirmationLabel("Combine")
            .fileDialogConfirmationLabel(Text("Combine"))
            .fileDialogConfirmationLabel(String("Combine"))
            .fileDialogDefaultDirectory(documents)
            .fileDialogDefaultDirectory(nil)
            .fileDialogBrowserOptions([.includeHiddenFiles, .enumeratePackages, .displayFileExtensions])
            .fileDialogURLEnabled(#Predicate<URL> { $0.pathExtension == "pdf" })
            .fileDialogImportsUnresolvedAliases(true)
            .fileDialogCustomizationID("combine")
    }
}

/// The four movers as Apple's documentation writes them.
@MainActor
private struct CorpusFileMovers: View {
    @State private var showFileMover = false
    var file: URL
    var files: [URL]
    var onCompletion: (URL) -> Void
    var onCancellation: (() -> Void)?

    var body: some View {
        VStack {
            Button {
                showFileMover = true
            } label: {
                Label("Choose destination", systemImage: "folder.circle")
            }
            .fileMover(isPresented: $showFileMover, file: file) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else { return }
                    onCompletion(url)
                    url.stopAccessingSecurityScopedResource()
                case .failure(let error):
                    print(error)
                }
            } onCancellation: {
                onCancellation?()
            }
            Button("Move") { showFileMover = true }
                .fileMover(isPresented: $showFileMover, file: Optional(file)) { _ in }
            Button("Move all") { showFileMover = true }
                .fileMover(isPresented: $showFileMover, files: files) { result in _ = result }
            Button("Move set") { showFileMover = true }
                .fileMover(isPresented: $showFileMover, files: Set(files)) { _ in } onCancellation: {}
        }
    }
}
