//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PropertyWalk+Access.swift
//
//  How the property walk reaches each kind of property at an address,
//  through its type: TUIkit's own properties' hooks and an app property's
//  `update()`, called on the value where it lies.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension StateBindable {
    /// ``StateBindable/bindState(to:key:)`` on the `@State` at `address`.
    static func bindState(at address: UnsafeMutableRawPointer, to storage: StateStorage, key: StateStorage.StateKey) {
        address.assumingMemoryBound(to: Self.self).pointee.bindState(to: storage, key: key)
    }
}

extension RenderIdentityBindable {
    /// ``RenderIdentityBindable/bindRenderIdentity(path:propertyIndex:)`` on
    /// the property at `address`.
    static func bindRenderIdentity(at address: UnsafeMutableRawPointer, path: String, propertyIndex: Int) {
        address.assumingMemoryBound(to: Self.self).pointee.bindRenderIdentity(path: path, propertyIndex: propertyIndex)
    }
}

extension EnvironmentResolvable {
    /// ``EnvironmentResolvable/resolveEnvironment(_:)`` on the property at
    /// `address`.
    static func resolveEnvironment(at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues) {
        address.assumingMemoryBound(to: Self.self).pointee.resolveEnvironment(environment)
    }
}

extension ResolvesOwnEnvironment {
    /// ``ResolvesOwnEnvironment/resolveOwnEnvironment(_:)`` on the view at
    /// `address` — and, the first time its type is drawn in a debug build, a
    /// check that it resolved every `@Environment` of its own.
    static func resolveOwnEnvironment(at address: UnsafeMutableRawPointer, _ environment: EnvironmentValues) {
        address.assumingMemoryBound(to: Self.self).pointee.resolveOwnEnvironment(environment)
        #if DEBUG
            OwnResolutionCheck.verify(Self.self, at: address)
        #endif
    }
}

#if DEBUG
    /// The ``ResolvesOwnEnvironment`` types whose own resolution a debug build
    /// has checked.
    @MainActor
    private enum OwnResolutionCheck {
        static var verified: Set<ObjectIdentifier> = []

        /// Checks, once per type, that the view at `address` of `type` had
        /// every `@Environment` of its own resolved.
        static func verify(_ type: Any.Type, at address: UnsafeMutableRawPointer) {
            guard verified.insert(ObjectIdentifier(type)).inserted else { return }
            for field in RuntimeFields.fields(of: type) {
                guard let inspectable = field.type as? any ResolutionInspectable.Type else { continue }
                assert(
                    inspectable.isResolved(at: address + field.offset),
                    "\(type).resolveOwnEnvironment(_:) does not resolve \(field.name)")
            }
        }
    }

    extension ResolutionInspectable {
        static func isResolved(at address: UnsafeMutableRawPointer) -> Bool {
            address.assumingMemoryBound(to: Self.self).pointee.isResolved
        }
    }
#endif

extension DynamicProperty {
    /// ``DynamicProperty/update()`` on the property at `address`, where it
    /// lies.
    static func updateInPlace(at address: UnsafeMutableRawPointer) {
        address.assumingMemoryBound(to: Self.self).pointee.update()
    }

    /// ``DynamicProperty/update()`` on a copy of the property at `address`,
    /// which is then dropped.
    static func updateCopy(at address: UnsafeMutableRawPointer) {
        var copy = address.assumingMemoryBound(to: Self.self).pointee
        copy.update()
    }

    /// ``DynamicProperty/update()`` on `object`, an instance of this type, a
    /// class.
    static func updateObject(_ object: AnyObject) {
        guard var property = object as? Self else { return }
        property.update()
    }
}
