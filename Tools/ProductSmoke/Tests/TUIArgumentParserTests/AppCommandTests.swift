//  🖥️ TUI — A Terminal UI framework for Swift
//  AppCommandTests.swift
//
//  Here rather than in Tests/ because it needs the trait `ArgumentParser`, which this fixture turns on the way a
//  client does and the package's own build leaves off. verify-products.sh runs it, and the launch itself from the
//  outside: help and mistakes on a pipe, with no byte of escape code.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIArgumentParser

private struct Viewer: App {
    var path = "unset"
    var depth = -1

    var body: some Scene {
        WindowGroup { Text(path) }
    }

    static func runWithoutTerminal(_ situation: NoTerminal) async -> NoTerminal.Outcome {
        .exit(23)
    }
}

private struct ViewerCommand: AppCommand {
    static let configuration = CommandConfiguration(commandName: "viewer")

    @Option(help: "The folder to show.")
    var path = "."

    @Option(help: "How deep to look.")
    var depth = 1

    var app: Viewer { Viewer(path: path, depth: depth) }

    func validate() throws {
        guard depth > 0 else { throw ValidationError("depth must be positive") }
    }
}

@Suite("AppCommand")
struct AppCommandTests {
    @Test("The values parsed reach the app")
    @MainActor
    func valuesReachTheApp() throws {
        let command = try ViewerCommand.parse(["--path", "/tmp", "--depth", "3"])
        #expect(command.app.path == "/tmp")
        #expect(command.app.depth == 3)
    }

    @Test("Values not given are the command's defaults, not the app's")
    @MainActor
    func defaults() throws {
        let command = try ViewerCommand.parse([])
        #expect(command.app.path == ".")
        #expect(command.app.depth == 1)
    }

    @Test("A mistake is an error with a message and a usage status, and makes no app")
    func mistakes() {
        for arguments in [["--nonsense"], ["--depth", "0"], ["--depth", "x"]] {
            #expect(throws: (any Error).self) { try ViewerCommand.parseAsRoot(arguments) }
            do {
                _ = try ViewerCommand.parseAsRoot(arguments)
            } catch {
                #expect(ViewerCommand.exitCode(for: error) == .validationFailure)
                #expect(!ViewerCommand.fullMessage(for: error).isEmpty)
            }
        }
    }

    @Test("Help names the options, and asks for no app")
    func help() throws {
        let text = ViewerCommand.helpMessage()
        #expect(text.contains("--path"))
        #expect(text.contains("The folder to show."))
    }

    #if !os(Windows)
        @Test("Running the command reaches the launch's terminal check, whose status is the process's")
        func runReachesTheLaunch() async {
            await #expect(processExitsWith: .exitCode(23)) {
                // An exit test has no terminal for its standard streams.
                let command = try? ViewerCommand.parse(["--path", "/tmp"])
                try? await command?.run()
            }
        }
    #endif
}
