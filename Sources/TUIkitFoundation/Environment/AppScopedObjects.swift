//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppScopedObjects.swift
//
//  One object of each type an optional module needs per app, made when first
//  asked for and kept for the app's life.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One object of each type per app — for a module the app context cannot
/// name.
///
/// An app's context (`TUIContext`) owns its services, but it can hold only
/// the types its own module sees, and the modules are à la carte: an app that
/// draws no images does not link the image module, so the context cannot own
/// that module's URL image cache. The module asks this for its object instead,
/// by type, and gets the same one for as long as the app runs — an app's own,
/// never one shared across the process (CLAUDE.md, No Singletons).
///
/// Main-actor only, as a render is: an object that work off the main actor
/// needs is looked up during the render and handed to that work.
@MainActor
package final class AppScopedObjects {
    private var objects: [ObjectIdentifier: AnyObject] = [:]

    /// Nonisolated: an app context, which owns one, is made before the run
    /// loop is on the main actor, and an empty box touches nothing.
    nonisolated package init() {}

    /// The app's object of type `T`, made by `make` the first time it is asked
    /// for.
    package func object<T: AnyObject>(_ make: () -> T) -> T {
        let key = ObjectIdentifier(T.self)
        if let existing = objects[key] as? T { return existing }
        let made = make()
        objects[key] = made
        return made
    }
}
