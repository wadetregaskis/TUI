//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RuntimeChildren.swift
//
//  A value's children as the runtime lists them — what `Mirror` shows a type
//  that has no `customMirror` — read through the runtime entry points
//  `Mirror` itself is built on, which never ask a `customMirror`.
//
//  Two uses: loading a field held `weak` or `unowned`, whose storage only the
//  runtime knows how to read for every kind of class (a typed load needs the
//  ownership, which the field metadata does not give beyond "not strong");
//  and an enum's current case and payload. Declared exactly as the standard
//  library declares them for itself (stdlib/public/core/ReflectionMirror.swift),
//  as `RuntimeFields`' entry points are; exported by the runtime on every
//  platform since Swift 5.
//
//  Created by Wade Tregaskis
//  License: MIT

/// How many children `value`, viewed as `type`, has: a struct's or a class's
/// own stored fields, or 1 for an enum whose case has a payload.
@_silgen_name("swift_reflectionMirror_count")
private func runtimeChildCount<T>(_: T, type: Any.Type) -> Int

/// How the runtime gives back a child's name.
private typealias RuntimeNameFree = @convention(c) (UnsafePointer<CChar>?) -> Void

/// The child at `index` of `value`, viewed as `type`, copied out as the
/// runtime reads it (a `weak` field as an optional; an `unowned` one loaded
/// strongly, which traps if its object has gone), and its name.
@_silgen_name("swift_reflectionMirror_subscript")
private func runtimeChild<T>(
    of: T, type: Any.Type, index: Int, outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
    outFreeFunc: UnsafeMutablePointer<RuntimeNameFree?>
) -> Any

/// A value's children, as the runtime's reflection lists them.
package enum RuntimeChildren {
    /// How many children `value` has, viewed as `type` — for a class
    /// instance, one of its classes, whose own fields are listed.
    package static func count<T>(of value: T, as type: Any.Type) -> Int {
        runtimeChildCount(value, type: type)
    }

    /// The child at `index` of `value`, viewed as `type`, and its name (`nil`
    /// where the runtime gives none).
    package static func child<T>(of value: T, as type: Any.Type, at index: Int) -> (name: String?, value: Any) {
        var name: UnsafePointer<CChar>?
        var free: RuntimeNameFree?
        let child = runtimeChild(of: value, type: type, index: index, outName: &name, outFreeFunc: &free)
        defer { free?(name) }
        return (name.map { String(cString: $0) }, child)
    }

    /// The child at `index` of `value`, viewed as `type`, without its name:
    /// a field loaded each body, which has no use for a string made of it.
    package static func value<T>(of value: T, as type: Any.Type, at index: Int) -> Any {
        var name: UnsafePointer<CChar>?
        var free: RuntimeNameFree?
        let child = runtimeChild(of: value, type: type, index: index, outName: &name, outFreeFunc: &free)
        free?(name)
        return child
    }
}
