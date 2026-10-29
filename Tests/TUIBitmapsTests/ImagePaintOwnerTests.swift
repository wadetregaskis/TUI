//  🖥️ TUI — A Terminal UI framework for Swift
//  ImagePaintOwnerTests.swift
//
//  An image drawn out of an object the app handed over — a `CGImage`, a bundle's
//  picture — is named by that object's address, and a freed address can come
//  straight back for a different picture. `Image` keeps the object it last drew
//  for as long as it keeps the name (`_ImageCore`'s owner box), so no other
//  picture can take the address meanwhile. An `ImagePaint` of the same picture
//  kept only the address, so the paint's pixels could outlive the object, and a
//  new picture at the old address was handed the old pixels.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@testable import TUIBitmaps
import TUIImage

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// What a picture is drawn out of: an object with an address, as a `CGImage` is.
private final class PictureOwner {}

@MainActor
@Suite("An image paint keeps the object its pixels were drawn out of")
struct ImagePaintOwnerTests {

    @Test("The object a paint's pixels came from lives as long as the paint keeps them")
    func paintKeepsItsOwner() throws {
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 8, availableHeight: 4, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))

        weak var released: PictureOwner?
        do {
            let owner = PictureOwner()
            released = owner
            let pixels = RGBAImage(width: 2, height: 1, pixels: [RGBA(r: 200, g: 0, b: 0), RGBA(r: 0, g: 0, b: 200)])
            let decoded = _DecodedImage(owner: owner) { pixels }
            // Named by the owner's address, as `Image(_:scale:orientation:label:)` names a `CGImage`.
            let address = String(UInt(bitPattern: ObjectIdentifier(owner).hashValue), radix: 16)
            let source = ImageSource.url("test-owner:\(address)")
            tui.stateStorage.beginRenderPass()
            let drawn = _ImageCore(source: source, decoded: decoded).paintPixels(context: context)
            tui.stateStorage.endRenderPass()
            #expect(drawn != nil, "the paint drew no pixels, so the case is vacuous")
        }
        #expect(
            released != nil,
            "the paint kept the pixels and let the object go, so its address can name another picture")
    }
}
