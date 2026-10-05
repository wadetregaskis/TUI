//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormContentExtraction.swift
//
//  How a `Form` reads its content as rows and sections: the walk its layout
//  lays out. Split out of `Form.swift`, which had passed the file-length
//  guideline.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Form Content Extraction

/// Views that can contribute rows/sections to a ``Form``.
///
/// Mirrors the ``ButtonProvider`` pattern ``Alert`` uses: the form walks its
/// content tree through this protocol to recover the label/control structure it
/// needs for pillar alignment (a generic `Form<Content>` can't otherwise see
/// inside its opaque content).
@MainActor
protocol FormContentExtractor {
    /// This view's elements, read where the form's walk is (`walk` — see
    /// ``formElements(from:in:)``).
    func extractFormElements(in walk: RenderContext) -> [_FormElement]
}

/// The identity step under a form at which its content walk starts: where a
/// view of the app's own the walk reads through binds its `@State`, apart from
/// the identities the form's rows draw at.
enum _FormContentWalk {}

/// Extracts the form elements of `view`: its own contribution if it is a
/// ``FormContentExtractor``; otherwise a control row (checkbox/radio), a button
/// row, the elements of the body of a view of the app's own whose body is
/// several views or a section, or a plain full-width row depending on its kind.
///
/// `walk` is the form's context with an identity for the place the walk has
/// reached: a step for each tuple slot, loop element, `if`/`else` arm and
/// section content it has passed through, below a step of its own under the
/// form (``_FormContentWalk``). It is where a view of the app's own read
/// through has its body evaluated, so its `@State` is bound at an address of
/// its own, the same every frame.
@MainActor
func formElements<V: View>(from view: V, in walk: RenderContext) -> [_FormElement] {
    if let aligned = view as? FormRowAligning {
        let alignment = aligned.formRowAlignmentValue
        return aligned.formRowInnerElements(in: walk).map { stamped($0, alignment: alignment) }
    }
    if let extractor = view as? FormContentExtractor {
        return extractor.extractFormElements(in: walk)
    }
    if view is FormControlRow {
        return [.row(_FormRow(.control(AnyView(view))))]
    }
    if view is FormButtonRow {
        return [.row(_FormRow(.button(AnyView(view))))]
    }
    // A view of the app's own whose body is several views, a loop, an `if` or
    // a section — what a stack takes apart (`compositeMembers(of:context:)`,
    // decisions D1S, B-D1S-6) — is read through its body, as SwiftUI's form
    // reads it (measured, `D1S/probe2/formcomposite`: such a section and such
    // rows lay out as written bare, in both styles): `struct General: View { var
    // body: some View { Section("General") { … } } }` is a section of the
    // form, its `Toggle` in the control column. It was a plain row, drawn as
    // the section's parts since a section outside a `List` became its parts
    // (B16). The body is evaluated as a render evaluates it — `@State` bound
    // here, `@Environment` resolved, observed — and read one step in.
    //
    // A view nested in itself through such bodies is read through at every
    // level, each a descent of this walk, so the walk stops where the stack
    // runs short, as `compositeMembers(of:context:)` stops: the view is then
    // the plain row below, drawn whole, and its own descent truncates under
    // the render's guard, which counts. Unguarded, a tree of a few thousand
    // levels in a form overflowed the stack.
    if isCompositeHandingOverChildren(V.self), walk.stateStorage != nil, StackGuard.hasHeadroomUncounted() {
        let body = evaluateCompositeBody(of: view, context: walk)
        return formElements(from: body, in: walk.withChildIdentity(type: V.Body.self))
    }
    return [.row(_FormRow(.plain(AnyView(view))))]
}

/// Stamps an explicit alignment onto an element's row(s), without clobbering an
/// inner override already present (the innermost `formRowAlignment` wins).
private func stamped(_ element: _FormElement, alignment: HorizontalAlignment) -> _FormElement {
    func apply(_ row: _FormRow) -> _FormRow {
        var row = row
        if row.alignment == nil { row.alignment = alignment }
        return row
    }
    switch element {
    case .row(let row):
        return .row(apply(row))
    case .section(var section):
        section.rows = section.rows.map { stamped($0, alignment: alignment) }
        return .section(section)
    case .group(let elements, let branch):
        return .group(elements.map { stamped($0, alignment: alignment) }, branch: branch)
    }
}

/// Flattens elements to their rows (a section contributes its rows, an `if`
/// the ones it holds).
func formRows(of elements: [_FormElement]) -> [_FormRow] {
    elements.flatMap { element -> [_FormRow] in
        switch element {
        case .row(let row): return [row]
        case .section(let section): return formRows(of: section.rows)
        case .group(let elements, _): return formRows(of: elements)
        }
    }
}

/// `elements` as a section's rows: a section among them — nested in the
/// section's content — contributes its rows, and an `if` keeps its place.
private func sectionRows(of elements: [_FormElement]) -> [_FormElement] {
    elements.flatMap { element -> [_FormElement] in
        switch element {
        case .row: return [element]
        case .section(let section): return section.rows
        case .group(let elements, let branch): return [.group(sectionRows(of: elements), branch: branch)]
        }
    }
}

extension LabeledContent: FormContentExtractor {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        [.row(_FormRow(.field(label: AnyView(label), content: AnyView(content))))]
    }
}

/// A collapsible section's header is a `List`'s — behind a disclosure
/// triangle, one control the keyboard and a click toggle — and its rows and
/// footer are drawn only while it is expanded, as SwiftUI collapses a form's
/// section in either style (measured on macOS 15.8, `D1S/probe2/form`).
extension Section: FormContentExtractor {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        let header: AnyView? =
            Parent.self == EmptyView.self
            ? nil
            : isExpanded.map { AnyView(_SectionHeader(header: self.header, isExpanded: $0)) } ?? AnyView(self.header)
        return [
            .section(
                _FormSection(
                    header: header,
                    footer: (footer is EmptyView || !showsContent) ? nil : AnyView(footer),
                    rows: showsContent
                        ? sectionRows(
                            of: formElements(from: content, in: walk.withChildIdentity(type: Content.self, index: 1)))
                        : [],
                    isOpen: showsContent))
        ]
    }
}

extension TupleView: FormContentExtractor {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        var elements: [_FormElement] = []
        var slot = 0
        func collect<T: View>(_ view: T) {
            elements.append(contentsOf: formElements(from: view, in: walk.withChildIdentity(erasedType: T.self, index: slot)))
            slot += 1
        }
        repeat collect(each children)
        return elements
    }
}

extension ForEach: FormContentExtractor where Content: View {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        data.flatMap { element in
            formElements(
                from: content(element),
                in: walk.withChildIdentity(erasedType: Content.self, key: identityKey(elementID(of: element))))
        }
    }
}

/// A form reads its rows through an erasure, as through a `Group` — which is
/// what lets ``Form/init(_:)`` lay out a configuration's type-erased content.
extension AnyView: FormContentExtractor {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        formElements(from: erasedView, in: walk)
    }
}

extension EmptyView: FormContentExtractor {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] { [] }
}

/// A form reads its rows through a `Group`, as SwiftUI's does: a section in
/// one is a section of the form, a control a control row (measured on macOS
/// 15.8, `D1S/probe2/form`). It was a plain row before, drawn as written — a
/// `Section` in one had no form styling, a `Toggle` no place in the control
/// column.
extension Group: FormContentExtractor where Content: View {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        formElements(from: content, in: walk)
    }
}

/// An `if`'s elements, kept in one place among the form's
/// (``_FormElement/group(_:branch:)``), as SwiftUI lays a section out in one
/// as it does written bare (measured). Nothing while the condition is false.
extension Optional: FormContentExtractor where Wrapped: View {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        [.group(map { formElements(from: $0, in: walk) } ?? [], branch: nil)]
    }
}

/// An `if`/`else`'s live arm's elements, kept in one place among the form's
/// and drawn under the arm's branch, so the arms keep their state apart.
extension ConditionalView: FormContentExtractor {
    func extractFormElements(in walk: RenderContext) -> [_FormElement] {
        switch self {
        case .trueContent(let content):
            [.group(formElements(from: content, in: walk.withBranchIdentity("true")), branch: "true")]
        case .falseContent(let content):
            [.group(formElements(from: content, in: walk.withBranchIdentity("false")), branch: "false")]
        }
    }
}
