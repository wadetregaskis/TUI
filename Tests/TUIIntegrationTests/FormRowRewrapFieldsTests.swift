//  🖥️ TUI — A Terminal UI framework for Swift
//  FormRowRewrapFieldsTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore
import TUIStyling

@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUIView

/// A form lays a modified row out by taking the modifier off and putting a copy
/// of it back around the row it lays out (``FormRowRewrapping``). The copy is
/// spelled out field by field, because its content is another type, and a field
/// with a default value can be left out without the compiler saying so: the copy
/// then quietly behaves as the default. An `.onContinuousHover` row lost its
/// sub-cell pointer locations that way, a `.task(name:)` row its name, a
/// key-titled alert its relocalisation and a sheet its size classes.
///
/// Each case here sets every field to something other than its default and
/// asks that the copy hold the same values, its content aside.
@MainActor
@Suite("Form row rewrapping keeps every field")
struct FormRowRewrapFieldsTests {

    /// The fields of `value` other than its content, each as it describes
    /// itself — a closure as `(Function)`, which says only that one is there.
    private static func fields(_ value: Any) -> [String: String] {
        var fields: [String: String] = [:]
        for child in Mirror(reflecting: value).children {
            guard let label = child.label, label != "content", label != "base" else { continue }
            fields[label] = String(describing: child.value)
        }
        return fields
    }

    /// Rewraps `modifier` around a fresh row and compares the copy's fields.
    private static func expectRewrapKeepsFields(_ modifier: some View, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let wrapper = modifier as? any FormRowRewrapping else {
            Issue.record("\(type(of: modifier)) does not rewrap a form row", sourceLocation: sourceLocation)
            return
        }
        let copy = wrapper.rewrappingFormRow(Text("row"))
        let original = fields(modifier)
        let rewrapped = fields(copy)
        #expect(!original.isEmpty, sourceLocation: sourceLocation)
        for (label, value) in original {
            #expect(
                rewrapped[label] == value, "\(type(of: modifier)).\(label): \(rewrapped[label] ?? "missing") ≠ \(value)",
                sourceLocation: sourceLocation)
        }
    }

    private static let anchor = ViewIdentity(rootType: Int.self).child(type: String.self)

    @Test("A continuous hover keeps asking where in the cell the pointer is")
    func continuousHover() {
        Self.expectRewrapKeepsFields(
            OnHoverModifier(content: Text("x"), coordinateSpace: .global, readsLocation: true) { _ in })
    }

    @Test("A task keeps its name, and a copy around one member its anchor")
    func task() {
        Self.expectRewrapKeepsFields(
            TaskModifier(
                content: Text("x"), task: {}, priority: .low, id: nil, name: "poll", anchor: Self.anchor))
    }

    @Test("An appearance, a disappearance and a change action keep their anchors")
    func lifecycleAnchors() {
        Self.expectRewrapKeepsFields(OnAppearModifier(content: Text("x"), action: {}, anchor: Self.anchor))
        Self.expectRewrapKeepsFields(OnDisappearModifier(content: Text("x"), action: {}, anchor: Self.anchor))
        var change = OnChangeModifier(content: Text("x"), value: 3, initial: true) { _, _ in }
        change.anchor = Self.anchor
        Self.expectRewrapKeepsFields(change)
    }

    @Test("A key-titled alert keeps the key it relocalises its title from")
    func alertTitleSource() {
        let alert = Text("x").titledAlert(
            "Delete?", isPresented: .constant(false), actions: EmptyView(), message: Text("m"),
            verticalButtons: true)
        #expect(alert.titleSource != nil)
        var erroring = alert
        erroring.presentsError = true
        Self.expectRewrapKeepsFields(erroring)
    }

    @Test("A sheet keeps its size classes and whether it docks while dismissed")
    func modalSizeClasses() {
        Self.expectRewrapKeepsFields(
            ModalPresentationModifier(
                content: Text("x"), isPresented: .constant(false), modal: { Text("sheet") }, style: .fullScreen,
                sizeClasses: PresentationSizeClasses(horizontal: .compact, vertical: .compact),
                postsDockWhileDismissed: false, itemKey: "item"))
    }
}
