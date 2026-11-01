//  🖥️ TUI — A Terminal UI framework for Swift
//  UnavailableCorpus.swift
//
//  SwiftUI code that TUI refuses on purpose, each line stating the error it gets.
//  compile_corpus.sh checks this with the compiler's `-verify` mode, which fails on
//  a missing error as well as on an extra one. So it proves that each call reaches
//  its stub (files named *+SwiftUIUnavailable.swift) with the stub's own message
//  and no cascade of others, and it fails when TUI gains the real thing and the
//  stub has to go.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

// A line holds a call and its expected error, however long that makes it.
// swiftlint:disable line_length private_swiftui_state

private struct Modifiers: View {
    @State var on = false
    @State var name = ""

    var body: some View {
        VStack {
            Text("a").foregroundColor(.red) // expected-error {{'foregroundColor' has been renamed to 'foregroundStyle(_:)': SwiftUI has deprecated}}
            Text("a").foregroundColor(Color.secondary) // expected-error {{'foregroundColor' has been renamed}}
            Text("a").accentColor(.red) // expected-error {{'accentColor' has been renamed to 'tint(_:)'}}
            Text("a").preferredColorScheme(.dark) // expected-error {{'preferredColorScheme' is unavailable: Set the look of your app}}
            Text("a").cornerRadius(8) // expected-error {{'cornerRadius(_:antialiased:)' is unavailable: A cell has square corners}}
            Text("a").edgesIgnoringSafeArea(.all) // expected-error {{'edgesIgnoringSafeArea' is unavailable: TUI has no safe area}}
            Color.red.ignoresSafeArea() // expected-error {{'ignoresSafeArea(_:edges:)' is unavailable: TUI has no safe area}}
            Text("a").ignoresSafeArea(.keyboard, edges: .bottom) // expected-error {{'ignoresSafeArea(_:edges:)' is unavailable}}
        }
        VStack {
            Text("a").overlay(Text("b"), alignment: .topLeading) // expected-error {{'overlay(_:alignment:)' is unavailable: Put the view in a closure}}
            Text("a").overlay(Circle().stroke(Color.red)) // expected-error {{'overlay(_:alignment:)' is unavailable}}
            Text("a").background(Text("b"), alignment: .leading) // expected-error {{'background(_:alignment:)' is unavailable: Put the view in a closure}}
            Text("a").background(RoundedRectangle(cornerRadius: 8).fill(Color.blue)) // expected-error {{'background(_:alignment:)' is unavailable}}
            Text("a").mask(Rectangle()) // expected-error {{'mask' is unavailable: Put the view in a closure}}
            Text("a").rotationEffect(.degrees(45)) // expected-error {{'rotationEffect(_:anchor:)' is unavailable: A character cell can't be rotated}}
            Text("a").rotation3DEffect(.degrees(45), axis: (x: 0, y: 1, z: 0)) // expected-error {{'rotation3DEffect(_:axis:anchor:anchorZ:perspective:)' is unavailable}}
            Text("a").scaleEffect(1.2) // expected-error {{'scaleEffect(_:anchor:)' is unavailable: A character cell can't be scaled}}
            Text("a").scaleEffect(on ? 1.4 : 1) // expected-error {{'scaleEffect(_:anchor:)' is unavailable}}
            Text("a").scaleEffect(x: 1.2, y: 2) // expected-error {{'scaleEffect(x:y:anchor:)' is unavailable}}
        }
        VStack {
            Text("a").blur(radius: 2) // expected-error {{'blur(radius:opaque:)' is unavailable: A terminal can't blur}}
            Text("a").padding().animation(.easeIn) // expected-error {{'animation' is unavailable: Say which value to watch}}
            Text("a").onChange(of: on) { newValue in print(newValue) } // expected-error {{'onChange(of:perform:)' is unavailable: The closure takes both values}}
            TextField("a", text: $name).disableAutocorrection(true) // expected-error {{'disableAutocorrection' has been renamed to 'autocorrectionDisabled(_:)'}}
            ScrollView(.horizontal, showsIndicators: false) { Text("a") } // expected-error {{'init(_:showsIndicators:content:)' is unavailable: Use ScrollView}}
            Text("a").kerning(1) // expected-error {{'kerning' is unavailable: Every character}}
            Text("a").tracking(1) // expected-error {{'tracking' is unavailable: Every character}}
            Text("a").minimumScaleFactor(0.5) // expected-error {{'minimumScaleFactor' is unavailable: All text in a terminal is one size}}
            Text("a").allowsTightening(true) // expected-error {{'allowsTightening' is unavailable: Every character}}
            Text("a") + Text("b") // expected-error {{'+' is unavailable: Join Text with interpolation}}
        }
        VStack {
            Text("a").font(.system(size: 20)) // expected-error {{'system(size:weight:design:)' is unavailable: A terminal draws all text in one font}}
            Text("a").font(.system(size: 20, weight: .bold)) // expected-error {{'system(size:weight:design:)' is unavailable}}
            Text("a").font(.custom("Menlo", size: 12)) // expected-error {{'custom(_:size:)' is unavailable}}
            Text("a").font(.system(.title, design: .rounded)) // expected-error {{'rounded' is unavailable: The terminal chooses the font}}
            Text("a").font(.system(.title, design: .serif)) // expected-error {{'serif' is unavailable}}
            Image(systemName: "globe").imageScale(.large) // expected-error {{'imageScale' is unavailable: A symbol is one character}}
            Image(systemName: "star").symbolRenderingMode(.hierarchical) // expected-error {{'symbolRenderingMode' is unavailable: A symbol is one character}}
            Text("a").onOpenURL { url in print(url) } // expected-error {{'onOpenURL(perform:)' is unavailable: Nothing can send a URL}}
            Text("a").sensoryFeedback(.success, trigger: on) // expected-error {{'sensoryFeedback(_:trigger:)' is unavailable: A terminal has no haptics}}
        }
        VStack {
            Text("a").accessibilityLabel("x") // expected-error {{'accessibilityLabel(_:isEnabled:)' is unavailable: A terminal has no accessibility tree}}
            Text("a").accessibilityLabel(Text("x")) // expected-error {{'accessibilityLabel(_:isEnabled:)' is unavailable}}
            Text("a").accessibilityHint("y") // expected-error {{'accessibilityHint(_:isEnabled:)' is unavailable}}
            Text("a").accessibilityValue("3 of 4") // expected-error {{'accessibilityValue(_:isEnabled:)' is unavailable}}
            Text("a").accessibilityHidden(true) // expected-error {{'accessibilityHidden(_:isEnabled:)' is unavailable}}
            Text("a").accessibilityIdentifier("id") // expected-error {{'accessibilityIdentifier(_:isEnabled:)' is unavailable: A terminal has no accessibility tree, so delete this. To name}}
            Text("a").accessibilityAddTraits(.isHeader) // expected-error {{'accessibilityAddTraits' is unavailable}}
            Text("a").accessibilityRemoveTraits([.isButton, .isLink]) // expected-error {{'accessibilityRemoveTraits' is unavailable}}
            Text("a").accessibilityElement(children: .combine) // expected-error {{'accessibilityElement(children:)' is unavailable}}
        }
        VStack {
            Text("a").accessibilityAction { } // expected-error {{'accessibilityAction' is unavailable}}
            Text("a").accessibilityAction(named: "Go") { } // expected-error {{'accessibilityAction(named:_:)' is unavailable}}
            Text("a").accessibilitySortPriority(1) // expected-error {{'accessibilitySortPriority' is unavailable}}
            Text("a").environmentObject(NSObject()) // expected-error {{'environmentObject' is unavailable: TUI watches only @Observable}}
        }
    }
}

private struct Navigation: View {
    @State var on = false

    var body: some View {
        // expected-error@+1 {{'NavigationView' has been renamed to 'NavigationStack': For columns, use NavigationSplitView}}
        NavigationView {
            VStack {
                NavigationLink(destination: Text("d")) { Text("x") } // expected-error {{'init(destination:label:)' is unavailable: Put the destination in a closure}}
                NavigationLink("x", destination: Text("d")) // expected-error {{'init(_:destination:)' is unavailable: Put the destination in a closure}}
                NavigationLink(destination: Text("d"), isActive: $on) { Text("x") } // expected-error {{'init(destination:isActive:label:)' is unavailable: Use NavigationLink(value:)}}
                Text("a").navigationBarTitle("t") // expected-error {{'navigationBarTitle' has been renamed to 'navigationTitle(_:)'}}
                Text("a").navigationBarTitle("t", displayMode: .inline) // expected-error {{'navigationBarTitle(_:displayMode:)' is unavailable}}
                Text("a").navigationBarTitleDisplayMode(.inline) // expected-error {{'navigationBarTitleDisplayMode' is unavailable}}
                Text("a").navigationBarHidden(true) // expected-error {{'navigationBarHidden' is unavailable}}
                Text("a").navigationViewStyle(.stack) // expected-error {{'navigationViewStyle' is unavailable}}
            }
        }
    }
}

private struct Sections: View {
    var body: some View {
        List {
            Section(header: Text("h")) { Text("a") } // expected-error {{'init(header:content:)' is unavailable: Write the header in a closure}}
            Section(footer: Text("f")) { Text("a") } // expected-error {{'init(footer:content:)' is unavailable: Write the footer in a closure}}
            Section(header: Text("h"), footer: Text("f")) { Text("a") } // expected-error {{'init(header:footer:content:)' is unavailable: Write these in closures}}
        }
        .listStyle(.inset(alternatesRowBackgrounds: true)) // expected-error {{'inset(alternatesRowBackgrounds:)' is unavailable: Use .listStyle(.inset)}}
    }
}

private struct Row: Identifiable {
    let id = 0
    let name = ""
}

private struct Tables: View {
    let rows = [Row()]

    var body: some View {
        Table(rows) {
            TableColumn("Name", value: \.name)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true)) // expected-error {{'inset(alternatesRowBackgrounds:)' is unavailable: Use .tableStyle(.inset)}}
    }
}

private struct Tabs: View {
    @State var selection = 0

    var body: some View {
        TabView {
            Text("a") // expected-error {{'buildExpression' is unavailable: A TabView holds tabs, not views}}
            Text("a").tabItem { Text("t") } // expected-error {{'tabItem' is unavailable: Write each tab as a Tab}} expected-error {{'buildExpression' is unavailable}}
        }
        TabView(selection: $selection) {
            Text("a").tabItem { Label("A", systemImage: "a") }.tag(0) // expected-error {{'tabItem' is unavailable}} expected-error {{'buildExpression' is unavailable}}
        }
        Text("a").tabItem { Text("t") } // expected-error {{'tabItem' is unavailable: Write each tab as a Tab}}
    }
}

// The old model types.
private final class Model {
    var count = 0
}

private struct Wrappers: View {
    @StateObject var owned = Model() // expected-error {{'StateObject' is unavailable: TUI watches only @Observable models}}
    @ObservedObject var watched: Model // expected-error {{'ObservedObject' is unavailable: TUI watches only @Observable models}}
    @EnvironmentObject var shared: Model // expected-error {{'EnvironmentObject' is unavailable: TUI watches only @Observable models}}

    var body: some View {
        Text("a")
    }
}

private struct Windows: Scene {
    var body: some Scene {
        WindowGroup {
            Text("a")
        }
        .defaultSize(width: 480, height: 600) // expected-error {{'defaultSize(width:height:)' is unavailable: An app fills the terminal window}}
        .defaultSize(CGSize(width: 1, height: 1)) // expected-error {{'defaultSize' is unavailable}}
        .windowResizability(.contentSize) // expected-error {{'windowResizability' is unavailable}}
        .windowStyle(.hiddenTitleBar) // expected-error {{'windowStyle' is unavailable}}
    }
}

// swiftlint:enable line_length private_swiftui_state
