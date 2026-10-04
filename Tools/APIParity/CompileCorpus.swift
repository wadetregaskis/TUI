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
