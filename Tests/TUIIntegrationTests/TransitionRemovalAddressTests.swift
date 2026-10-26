//  🖥️ TUI — A Terminal UI framework for Swift
//  TransitionRemovalAddressTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIFoundation
@testable import TUITestSupport

/// What stands around the optional a view comes and goes through.
///
/// A removal plays in the slot the `nil` keeps, and the `nil` finds what the
/// view left behind by the view's ADDRESS — so every shape here has to address
/// the present view and the `nil` the same way.
enum RemovalSurround: String, CaseIterable, Sendable {
    /// `if` beside a sibling: the one shape that always worked. The control.
    case besideSibling
    /// The optional under `.frame` — the Example's Animation page.
    case framedBesideSibling
    /// The optional under `.opacity`, another wrapper that distributes.
    case fadedBesideSibling
    /// The optional under `.disabled`, a third.
    case disabledBesideSibling
    /// The optional under `.padding`, a `BufferModifier` that `ModifiedView`
    /// carries to each member rather than a wrapper that re-wraps it.
    case paddedBesideSibling
    /// The optional under `.background`, another.
    case backgroundBesideSibling
    /// The optional under `.id`, which adds an identity step of its own.
    case identifiedBesideSibling
    /// `Group { if … }.frame(…)`, the way SwiftUI code writes the frame.
    case framedGroupBesideSibling
    /// `VStack { if … }`: the optional is the container's only content.
    case onlyContent
    /// The same, framed.
    case framedOnlyContent
    /// The optional is all of one branch of an `if`/`else`.
    case loneBranch
    /// `if outer { if inner { … } }`, removed by the OUTER condition.
    case nestedIfBesideSibling
    /// The same as a stack's only content.
    case nestedIfOnlyContent
    /// `if outer { if inner { … } }` removed by the INNER condition, which the
    /// outer optional flattens.
    case nestedIfInnerRemoved
    /// `if … { Group { … } }`: a provider holding one member.
    case groupInIfBesideSibling
    /// The same as a stack's only content.
    case groupInIfOnlyContent
    /// `if … { if a { … } else { … } }`, removed by the outer condition.
    case conditionalInIfBesideSibling
    /// The same as a stack's only content.
    case conditionalInIfOnlyContent
    /// `if … { if a { Group { … } } else { … } }`: the providers composed.
    case groupInConditionalInIf
    /// `if … { Group { … }.padding(…) }`: one view, but behind a modifier on
    /// the structure around it, whose picture the `nil` could not draw.
    case paddedGroupInIf
    /// `if … { Group { … }.foregroundStyle(…) }`: a modifier on the structure
    /// that draws nothing of its own, but re-wraps the member it reaches.
    case styledGroupInIf

    /// Whether the removal does not play its own transition in this shape —
    /// the view goes at once instead — a gap on the record in
    /// ``View/transition(_:)``, pinned as a known issue so that closing it is
    /// noticed. `.id` puts an identity step of its own between the slot the
    /// `nil` claims and the view that left its picture, so the picture is one
    /// step below where the `nil` looks for it. A padded `Group` has a picture
    /// of its own the transition's would lose. The stack sees both go, and
    /// keeps no picture of them to fade: what goes from a stack with no
    /// transition it can play goes at once (decisions TR2PERF). A styled
    /// `Group` plays: its member, which the `nil` holding the wrapped `Group`
    /// could not name, is a child of the stack, and the stack sees it go
    /// (`ChildFade`).
    var goesAtOnce: Bool {
        self == .identifiedBesideSibling || self == .paddedGroupInIf
    }

    /// Whether the shape pads the view two cells in, beside a wider sibling.
    private var isPadded: Bool { self == .paddedBesideSibling || self == .paddedGroupInIf }

    /// The rows drawn under the optional: none, or a sibling.
    var sibling: [String] {
        switch self {
        case .onlyContent, .framedOnlyContent, .loneBranch, .nestedIfOnlyContent,
            .groupInIfOnlyContent, .conditionalInIfOnlyContent:
            []
        default:
            isPadded ? ["------"] : ["----"]
        }
    }

    /// The row `core` — the view, or what is left of it part-way gone — as
    /// the shape draws it.
    func drawn(_ core: String) -> String {
        isPadded ? "  " + core : core
    }
}

private struct Surrounded: View {
    let showing: Bool
    let surround: RemovalSurround
    /// Read by the shapes with a second condition, so each `if` is a real one.
    let other = true

    var body: some View {
        let panel = showing ? Text("XXXX").transition(.move(edge: .trailing)) : nil
        switch surround {
        case .besideSibling:
            VStack(spacing: 0) {
                panel
                Text("----")
            }
        case .framedBesideSibling:
            VStack(spacing: 0) {
                panel.frame(height: nil, alignment: .top)
                Text("----")
            }
        case .fadedBesideSibling:
            VStack(spacing: 0) {
                panel.opacity(1)
                Text("----")
            }
        case .disabledBesideSibling:
            VStack(spacing: 0) {
                panel.disabled(false)
                Text("----")
            }
        case .paddedBesideSibling:
            VStack(alignment: .leading, spacing: 0) {
                panel.padding(.leading, 2)
                Text("------")
            }
        case .backgroundBesideSibling:
            VStack(spacing: 0) {
                panel.background(Color.red)
                Text("----")
            }
        case .identifiedBesideSibling:
            VStack(spacing: 0) {
                panel.id("panel")
                Text("----")
            }
        case .framedGroupBesideSibling:
            VStack(spacing: 0) {
                Group {
                    if showing { Text("XXXX").transition(.move(edge: .trailing)) }
                }
                .frame(height: nil, alignment: .top)
                Text("----")
            }
        case .onlyContent:
            VStack(spacing: 0) { panel }
        case .framedOnlyContent:
            VStack(spacing: 0) { panel.frame(height: nil, alignment: .top) }
        case .loneBranch:
            VStack(spacing: 0) {
                if other { panel } else { Text("never") }
            }
        case .nestedIfBesideSibling:
            VStack(spacing: 0) {
                if showing { if other { Text("XXXX").transition(.move(edge: .trailing)) } }
                Text("----")
            }
        case .nestedIfOnlyContent:
            VStack(spacing: 0) {
                if showing { if other { Text("XXXX").transition(.move(edge: .trailing)) } }
            }
        case .nestedIfInnerRemoved:
            VStack(spacing: 0) {
                if other { panel }
                Text("----")
            }
        case .groupInIfBesideSibling:
            VStack(spacing: 0) {
                if showing { Group { Text("XXXX").transition(.move(edge: .trailing)) } }
                Text("----")
            }
        case .groupInIfOnlyContent:
            VStack(spacing: 0) {
                if showing { Group { Text("XXXX").transition(.move(edge: .trailing)) } }
            }
        case .conditionalInIfBesideSibling:
            VStack(spacing: 0) {
                if showing {
                    if other { Text("XXXX").transition(.move(edge: .trailing)) } else { Text("never") }
                }
                Text("----")
            }
        case .conditionalInIfOnlyContent:
            VStack(spacing: 0) {
                if showing {
                    if other { Text("XXXX").transition(.move(edge: .trailing)) } else { Text("never") }
                }
            }
        case .groupInConditionalInIf:
            VStack(spacing: 0) {
                if showing {
                    if other {
                        Group { Text("XXXX").transition(.move(edge: .trailing)) }
                    } else {
                        Text("never")
                    }
                }
                Text("----")
            }
        case .paddedGroupInIf:
            VStack(alignment: .leading, spacing: 0) {
                if showing {
                    Group { Text("XXXX").transition(.move(edge: .trailing)) }.padding(.leading, 2)
                }
                Text("------")
            }
        case .styledGroupInIf:
            VStack(spacing: 0) {
                if showing {
                    Group { Text("XXXX").transition(.move(edge: .trailing)) }.foregroundStyle(.red)
                }
                Text("----")
            }
        }
    }
}

/// What the `if` holds, beside a sibling: the view carrying the transition,
/// with or without something between it and the `if`.
enum RemovedView: String, CaseIterable, Sendable {
    /// `X.transition(t)`: the transition is the view the `if` holds.
    case transitionOutermost
    /// `X.id(k).transition(t)`: an identity step below the transition.
    case identifiedInside
    /// `X.transition(t).id(k)`: an identity step above it.
    case identifiedOutside
    /// A custom view whose `body` is `X.transition(t)`.
    case customViewBody
    /// `X.transition(t).tag(1)`: a modifier built as a view with a `body`.
    case taggedOutside
    /// `X.transition(t).sheet(…)`: a presentation modifier, which draws its
    /// content a step below itself.
    case presentingOutside
    /// `X.transition(t).foregroundStyle(.red)`: a modifier outside the
    /// transition that draws nothing of its own.
    case styledOutside
    /// `X.transition(t).onAppear { … }`: another — the commonest toast there
    /// is.
    case appearingOutside
    /// `AnyView(X.transition(t))`: a wrapper that draws its content unchanged
    /// but does not say what that content is.
    case erased
    /// `AnyView(X.transition(t)).onAppear { … }`: the two kinds nested, the
    /// eraser inside.
    case erasedThenAppearing
    /// `AnyView(X.transition(t).onAppear { … })`: the eraser outside.
    case appearingThenErased
    /// `X.transition(t).disabled(false)`: an environment modifier that also
    /// re-wraps the members of what it wraps.
    case disabledOutside
    /// `X.transition(t).onPreferenceChange(…)`: a wrapper that draws nothing
    /// of its own but is not yet looked through (not a single-content
    /// wrapper), with `.appHeader` and the two status-bar item modifiers.
    case preferenceObservedOutside

    /// Whether the removal does not play its own transition — it fades
    /// instead — a gap on the record in ``View/transition(_:)``, pinned as a
    /// known issue. An `.id` outside the
    /// transition, a custom view's `body`, `.tag` and `.sheet` put an identity
    /// step between the slot the `nil` claims and the transition: `.id`'s own,
    /// and the step a `body` or a presentation's content renders at. The
    /// wrappers that draw their content unchanged play: the slot looks through
    /// them (`DrawsContentUnchanged`), or the `AnyView` vouches for its picture.
    var fadesInstead: Bool {
        switch self {
        case .identifiedOutside, .customViewBody, .taggedOutside, .presentingOutside,
            .preferenceObservedOutside:
            true
        default: false
        }
    }
}

/// A preference nothing sets, for `.onPreferenceChange` to observe.
private struct ObservedPreference: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}

/// A custom view whose body carries the transition.
private struct SlidingCard: View {
    var body: some View { Text("XXXX").transition(.move(edge: .trailing)) }
}

private struct Held: View {
    let showing: Bool
    let held: RemovedView

    /// The view that comes and goes, carrying its transition.
    private var sliding: some View { Text("XXXX").transition(.move(edge: .trailing)) }

    /// `view` in an `if`, beside a sibling. A function per shape rather than a
    /// `switch` inside the `if`, which would make what the `if` holds an
    /// `if`/`else` in every shape.
    private func besideSibling<V: View>(_ view: V) -> some View {
        VStack(spacing: 0) {
            if showing { view }
            Text("----")
        }
    }

    var body: some View {
        switch held {
        case .transitionOutermost: besideSibling(sliding)
        case .identifiedInside: besideSibling(Text("XXXX").id("k").transition(.move(edge: .trailing)))
        case .identifiedOutside: besideSibling(sliding.id("k"))
        case .customViewBody: besideSibling(SlidingCard())
        case .taggedOutside: besideSibling(sliding.tag(1))
        case .presentingOutside: besideSibling(sliding.sheet(isPresented: .constant(false)) { Text("sheet") })
        case .styledOutside: besideSibling(sliding.foregroundStyle(.red))
        case .appearingOutside: besideSibling(sliding.onAppear {})
        case .erased: besideSibling(AnyView(sliding))
        case .erasedThenAppearing: besideSibling(AnyView(sliding).onAppear {})
        case .appearingThenErased: besideSibling(AnyView(sliding.onAppear {}))
        case .disabledOutside: besideSibling(sliding.disabled(false))
        case .preferenceObservedOutside:
            besideSibling(sliding.onPreferenceChange(ObservedPreference.self) { _ in })
        }
    }
}

/// What the optional holds when it is rendered DIRECTLY — a view's whole
/// `body`, as here, or a modifier's content — rather than flattened into a
/// stack. There the optional hands its view its own identity, so the `nil`
/// looks for the picture at that identity, left by the innermost view through
/// nested optionals.
enum RenderedDirectly: String, CaseIterable, Sendable {
    /// `if a { X.transition(t) }`.
    case plain
    /// `if a { if b { X.transition(t) } }`, removed by the outer condition.
    case nestedIf
    /// `if a { Group { X.transition(t) } }`.
    case groupInIf
    /// `if a { if b { X.transition(t) } else { Y } }`, removed by the outer
    /// condition.
    case conditionalInIf
    /// `if a { X.transition(t).onAppear { … } }`: a wrapper that draws its
    /// content unchanged, at its own identity.
    case appearingOutside
    /// `if a { AnyView(X.transition(t)) }`: another, which says so only as it
    /// draws.
    case erased
    /// `AnyView(a ? X.transition(t) : nil)`: the optional inside the eraser,
    /// whose `nil` must still find the picture the eraser vouched for.
    case optionalInsideErased
    /// `if a { Group { X.transition(t) }.padding() }`: one view behind a
    /// modifier on the structure around it that draws. In a stack it goes at
    /// once (``RemovalSurround/paddedGroupInIf``); here the `if` holds it.
    case paddedGroupInIf
    /// `(a ? X.transition(t) : nil).id(k)`: `.id` written on the `if`, whose
    /// view goes at once in a stack
    /// (``RemovalSurround/identifiedBesideSibling``).
    case identified

    /// Whether the removal does not play its own transition — it fades
    /// instead — a gap on the record in ``View/transition(_:)``, pinned as a
    /// known issue. A `Group` draws its view one step below the optional's
    /// identity, where a view with a `body` draws its body, and an
    /// `if`/`else` draws its view under a branch step; the `nil` looks for
    /// the picture at its own identity. A padded `Group` has a picture of its
    /// own the transition's would lose. The `if` holds each of them, and
    /// fades the whole of what it held.
    var fadesInstead: Bool { self == .groupInIf || self == .conditionalInIf || self == .paddedGroupInIf }

    /// The row `core` — the view, or what is left of it part-way gone — as
    /// the shape draws it: two cells in, for the padded one.
    func drawn(_ core: String) -> String {
        self == .paddedGroupInIf ? "  " + core : core
    }
}

private struct HeldDirectly: View {
    let showing: Bool
    let shape: RenderedDirectly
    /// Read by the shapes with a second condition, so each `if` is a real one.
    let other = true

    var body: some View {
        switch shape {
        case .plain:
            if showing { Text("XXXX").transition(.move(edge: .trailing)) }
        case .nestedIf:
            if showing { if other { Text("XXXX").transition(.move(edge: .trailing)) } }
        case .groupInIf:
            if showing { Group { Text("XXXX").transition(.move(edge: .trailing)) } }
        case .conditionalInIf:
            if showing {
                if other { Text("XXXX").transition(.move(edge: .trailing)) } else { Text("never") }
            }
        case .appearingOutside:
            if showing { Text("XXXX").transition(.move(edge: .trailing)).onAppear {} }
        case .erased:
            if showing { AnyView(Text("XXXX").transition(.move(edge: .trailing))) }
        case .optionalInsideErased:
            AnyView(showing ? Text("XXXX").transition(.move(edge: .trailing)) : nil)
        case .paddedGroupInIf:
            if showing { Group { Text("XXXX").transition(.move(edge: .trailing)) }.padding(.leading, 2) }
        case .identified:
            (showing ? Text("XXXX").transition(.move(edge: .trailing)) : nil).id("panel")
        }
    }
}

@MainActor
@Suite("A removal plays out whatever stands around the optional")
struct TransitionRemovalAddressTests {

    /// A removal that did not play is a view that is simply gone on the frame
    /// it was removed. One that plays slides out where the view was, while the
    /// row below glides up into the room it gave back at once (`StackGlide`,
    /// drawn in by `RemovalScreen`). Sampled at the start, half-way and after
    /// the end of a one-second slide.
    @Test("The removal slides out over its second where the view was",
        arguments: RemovalSurround.allCases)
    func removalPlaysOut(surround: RemovalSurround) {
        let screen = RemovalScreen(animation: .linear(duration: 1)) {
            Surrounded(showing: $0, surround: surround)
        }
        let sibling = surround.sibling

        // Arrive, and let the arrival finish: a view removed mid-arrival
        // departs from where its arrival had got, not from full presence.
        _ = screen.draw(true, atMillis: 0)
        #expect(
            screen.draw(true, atMillis: 1100) == [surround.drawn("XXXX")] + sibling,
            "precondition: it arrived")

        withKnownIssue("this shape's removal goes at once — see `goesAtOnce`") {
            #expect(
                screen.draw(false, atMillis: 1100) == [surround.drawn("XXXX")] + sibling,
                "gone on the frame it was removed")
            #expect(
                screen.draw(false, atMillis: 1600) == [surround.drawn("  XX")] + sibling,
                "not sliding out half-way")
        } when: {
            surround.goesAtOnce
        }
        if surround.goesAtOnce {
            #expect(screen.fades(false, atMillis: 1600).isEmpty, "gone, with nothing fading where it was")
        }
        #expect(screen.draw(false, atMillis: 2200) == sibling, "still drawn after the end")
    }

    /// The other half of the contract, for every shape: a `nil` nothing is
    /// leaving from takes no row, so nothing about an `if` changes for an app
    /// that animates nothing.
    @Test("A removal with no animation is instant", arguments: RemovalSurround.allCases)
    func unanimatedRemovalSnaps(surround: RemovalSurround) {
        let screen = RemovalScreen(animation: nil) { Surrounded(showing: $0, surround: surround) }
        #expect(screen.draw(true, atMillis: 0) == [surround.drawn("XXXX")] + surround.sibling)
        #expect(screen.draw(false, atMillis: 100) == surround.sibling)
    }

    /// The other axis: what the `if` holds. The slot is found by the address
    /// of the view carrying the transition, and drawn only if that view is
    /// what the `if` held, so an identity step or a modifier between the two
    /// leaves a removal that fades instead.
    @Test("The removal plays when the transition is on the view the if holds",
        arguments: RemovedView.allCases)
    func removalPlaysByWhatIsHeld(held: RemovedView) {
        let screen = RemovalScreen(animation: .linear(duration: 1)) { Held(showing: $0, held: held) }
        _ = screen.draw(true, atMillis: 0)
        #expect(screen.draw(true, atMillis: 1100) == ["XXXX", "----"], "precondition: it arrived")
        withKnownIssue("this removal fades instead — see `RemovedView.fadesInstead`") {
            #expect(screen.draw(false, atMillis: 1100) == ["XXXX", "----"], "gone on the frame it was removed")
            #expect(screen.draw(false, atMillis: 1600) == ["  XX", "----"], "not sliding out half-way")
        } when: {
            held.fadesInstead
        }
        if held.fadesInstead {
            #expect(!screen.fades(false, atMillis: 1600).isEmpty, "it fades where it was instead")
        }
        #expect(screen.draw(false, atMillis: 2200) == ["----"], "still drawn after the end")
    }

    /// The third axis: no stack at all. A `nil` rendered directly draws the
    /// picture left at its own identity, and nothing holds a row open around
    /// it but its own size.
    @Test("An optional rendered directly plays the removal of what it held",
        arguments: RenderedDirectly.allCases)
    func removalPlaysRenderedDirectly(shape: RenderedDirectly) {
        let screen = RemovalScreen(animation: .linear(duration: 1)) {
            HeldDirectly(showing: $0, shape: shape)
        }
        _ = screen.draw(true, atMillis: 0)
        #expect(screen.draw(true, atMillis: 1100) == [shape.drawn("XXXX")], "precondition: it arrived")
        withKnownIssue("this removal fades instead — see `RenderedDirectly.fadesInstead`") {
            #expect(screen.draw(false, atMillis: 1100) == [shape.drawn("XXXX")], "gone on the frame it was removed")
            #expect(screen.draw(false, atMillis: 1600) == [shape.drawn("  XX")], "not sliding out half-way")
        } when: {
            shape.fadesInstead
        }
        if shape.fadesInstead {
            #expect(!screen.fades(false, atMillis: 1600).isEmpty, "it fades where it was instead")
        }
        #expect(screen.draw(false, atMillis: 2200).isEmpty, "still drawn after the end")
    }
}
