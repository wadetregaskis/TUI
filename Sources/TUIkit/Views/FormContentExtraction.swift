//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormContentExtraction.swift
//
//  How a `Form` reads its content as rows and sections: the walk its layout
//  lays out. Split out of `Form.swift`, which had passed the file-length
//  guideline.
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Form Content Extraction

/// Views that can contribute rows/sections to a ``Form``.
///
/// Mirrors the ``ButtonProvider`` pattern ``Alert`` uses: the form walks its
/// content tree through this protocol to recover the label/control structure it
/// needs for pillar alignment (a generic `Form<Content>` can't otherwise see
/// inside its opaque content).
@MainActor
protocol FormContentExtractor {
    func extractFormElements() -> [_FormElement]
}

/// Extracts the form elements of `view`: its own contribution if it is a
/// ``FormContentExtractor``; otherwise a control row (checkbox/radio), a button
/// row, or a plain full-width row depending on its kind.
@MainActor
func formElements(from view: some View) -> [_FormElement] {
    if let aligned = view as? FormRowAligning {
        let alignment = aligned.formRowAlignmentValue
        return aligned.formRowInnerElements().map { stamped($0, alignment: alignment) }
    }
    if let extractor = view as? FormContentExtractor {
        return extractor.extractFormElements()
    }
    if view is FormControlRow {
        return [.row(_FormRow(.control(AnyView(view))))]
    }
    if view is FormButtonRow {
        return [.row(_FormRow(.button(AnyView(view))))]
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
    func extractFormElements() -> [_FormElement] {
        [.row(_FormRow(.field(label: AnyView(label), content: AnyView(content))))]
    }
}

extension Section: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        [.section(_FormSection(
            header: (header is EmptyView) ? nil : AnyView(header),
            footer: (footer is EmptyView) ? nil : AnyView(footer),
            rows: sectionRows(of: formElements(from: content))))]
    }
}

extension TupleView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        var elements: [_FormElement] = []
        func collect<T: View>(_ view: T) {
            elements.append(contentsOf: formElements(from: view))
        }
        repeat collect(each children)
        return elements
    }
}

extension ForEach: FormContentExtractor where Content: View {
    func extractFormElements() -> [_FormElement] {
        data.flatMap { element in formElements(from: content(element)) }
    }
}

/// A form reads its rows through an erasure, as through a `Group` — which is
/// what lets ``Form/init(_:)`` lay out a configuration's type-erased content.
extension AnyView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        formElements(from: erasedView)
    }
}

extension EmptyView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] { [] }
}

/// A form reads its rows through a `Group`, as SwiftUI's does: a section in
/// one is a section of the form, a control a control row (measured on macOS
/// 15.8, `D1S/probe2/form`). It was a plain row before, drawn as written — a
/// `Section` in one had no form styling, a `Toggle` no place in the control
/// column.
extension Group: FormContentExtractor where Content: View {
    func extractFormElements() -> [_FormElement] {
        formElements(from: content)
    }
}

/// An `if`'s elements, kept in one place among the form's
/// (``_FormElement/group(_:branch:)``), as SwiftUI lays a section out in one
/// as it does written bare (measured). Nothing while the condition is false.
extension Optional: FormContentExtractor where Wrapped: View {
    func extractFormElements() -> [_FormElement] {
        [.group(map { formElements(from: $0) } ?? [], branch: nil)]
    }
}

/// An `if`/`else`'s live arm's elements, kept in one place among the form's
/// and drawn under the arm's branch, so the arms keep their state apart.
extension ConditionalView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        switch self {
        case .trueContent(let content): [.group(formElements(from: content), branch: "true")]
        case .falseContent(let content): [.group(formElements(from: content), branch: "false")]
        }
    }
}
