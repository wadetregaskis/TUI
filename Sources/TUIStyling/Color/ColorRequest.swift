//  🖥️ TUI — A Terminal UI framework for Swift
//  ColorRequest.swift
//
//  What the person running the program said about colour, through the
//  environment. One reading, so that everything that asks gets the same answer.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What the environment says the person running the program wants of colour.
package enum ColorRequest: Equatable, Sendable {
    /// Nothing: colour is up to what the terminal can do and where the output goes.
    case unstated

    /// No colour.
    case off

    /// Colour, wherever the output goes.
    case forced

    /// Reads the request from `environment`.
    ///
    /// A parameter rather than a read of the process's, as
    /// ``ColorDepth/detect(environment:)`` is, so a test can pose a table
    /// without writing to the environment.
    package init(environment: [String: String]) {
        if let force = Self.stated("FORCE_COLOR", in: environment) {
            self = force == "0" ? .off : .forced
        } else {
            self = Self.stated("NO_COLOR", in: environment) == nil ? .unstated : .off
        }
    }

    /// The value of the variable `name`, unless it is missing or empty: an
    /// empty variable is taken as unset.
    package static func stated(_ name: String, in environment: [String: String]) -> String? {
        guard let value = environment[name], !value.isEmpty else { return nil }
        return value
    }
}
