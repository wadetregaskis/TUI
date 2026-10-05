//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+Resolve.swift
//
//  A colour resolved against an environment to numbers, and the resolved
//  value as a style and an animatable — the half of `Color.Resolved` that
//  needs the environment and the animation types.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

extension Color {
    /// Evaluates this colour within the given environment: its palette role, or
    /// the colour the terminal reported for a slot, as numbers.
    ///
    /// A terminal slot the terminal has not reported reads as xterm's value for
    /// it. The terminal's default ink and page are not known until reported;
    /// meanwhile they read as white and black on a dark scheme, black and white
    /// on a light one.
    ///
    /// - Parameter environment: The environment to resolve in.
    /// - Returns: The colour's components.
    public func resolve(in environment: EnvironmentValues) -> Resolved {
        let resolved = resolve(with: environment.palette)
        let opacity = Float(resolved.alpha) / 255
        if let (red, green, blue) = resolved.estimatedRGB {
            return Resolved(red: Float(red) / 255, green: Float(green) / 255, blue: Float(blue) / 255, opacity: opacity)
        }
        let isPage = resolved.value == .terminalBackground
        let light: Float = (environment.colorScheme == .dark) == isPage ? 0 : 1
        return Resolved(red: light, green: light, blue: light, opacity: opacity)
    }
}

extension Color.Resolved: ShapeStyle {
    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(Color(self))
    }
}

extension Color.Resolved: Animatable {
    /// The linear components and the opacity. SwiftUI animates a resolved
    /// colour in a space of its own that it does not document; linear light is
    /// what this one interpolates in.
    public typealias AnimatableData = AnimatablePair<Float, AnimatablePair<Float, AnimatablePair<Float, Float>>>

    public var animatableData: AnimatableData {
        get { AnimatablePair(linearRed, AnimatablePair(linearGreen, AnimatablePair(linearBlue, opacity))) }
        set {
            linearRed = newValue.first
            linearGreen = newValue.second.first
            linearBlue = newValue.second.second.first
            opacity = newValue.second.second.second
        }
    }
}
