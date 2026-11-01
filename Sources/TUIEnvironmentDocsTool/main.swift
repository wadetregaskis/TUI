//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  `swift run tui-environment-docs`: prints the table of environment variables in the
//  format asked for, or writes it to a file, for a build or release script. Upgrading
//  TUI then updates what it writes. It's built when someone runs it, and at no other time.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIEnvironmentDocs

/// What the command line asked for.
struct Options {
    enum Format: String {
        case man, mdoc, markdown
    }

    var format = Format.man
    var audience = TUIEnvironmentVariable.Audience.endUser
    var includesHeading = true
    var output: String?

    /// Reads `arguments`, or throws what to tell the person.
    init(arguments: [String]) throws(UsageError) {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--format":
                let value = remaining.popFirst() ?? ""
                guard let format = Format(rawValue: value) else {
                    throw UsageError("--format takes man, mdoc or markdown, not \"\(value)\"")
                }
                self.format = format
            case "--audience":
                let value = remaining.popFirst() ?? ""
                guard let audience = Self.audiences[value] else {
                    throw UsageError("--audience takes end-user, developer or detected, not \"\(value)\"")
                }
                self.audience = audience
            case "--no-heading":
                includesHeading = false
            case "--output":
                guard let path = remaining.popFirst() else { throw UsageError("--output takes a file") }
                output = path
            default:
                throw UsageError("unknown option \"\(argument)\"")
            }
        }
    }

    private static let audiences: [String: TUIEnvironmentVariable.Audience] = [
        "end-user": .endUser, "developer": .developer, "detected": .detected,
    ]

    /// The text this asks for.
    var text: String {
        switch format {
        case .man:
            TUIEnvironmentVariables.manPageSection(format: .man, audience: audience, includesHeading: includesHeading)
        case .mdoc:
            TUIEnvironmentVariables.manPageSection(format: .mdoc, audience: audience, includesHeading: includesHeading)
        case .markdown:
            TUIEnvironmentVariables.markdownSection(audience: audience)
        }
    }
}

struct UsageError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

let usage = """
    Prints the environment variables TUI reads, for an app's documentation.

      --format man|mdoc|markdown             Man page macros, or Markdown. man by default.
      --audience end-user|developer|detected Whose variables. end-user by default.
      --no-heading                           Leaves out a man page's ENVIRONMENT heading.
      --output FILE                          Writes FILE, and any directories it needs, rather than printing.

    """

/// Rewrites the generated tables of TUI's own article (`swift run tui-environment-docs
/// --update-article`, from a checkout), which a test holds to the table. For TUI's
/// developers, so not in the usage above.
func updateArticle(at path: String) throws {
    var page = try String(contentsOfFile: path, encoding: .utf8)
    let blocks: [(name: String, text: String)] = [
        ("end-user", TUIEnvironmentVariables.markdownTables(audience: .endUser)),
        ("developer", TUIEnvironmentVariables.markdownTables(audience: .developer)),
        ("detected", TUIEnvironmentVariables.markdownTables(audience: .detected)),
        ("code", TUIEnvironmentVariables.markdownCodeSettings()),
    ]
    for block in blocks {
        guard let opening = page.range(of: "<!-- tui-environment-docs: \(block.name) -->\n"),
            let closing = page.range(of: "<!-- /tui-environment-docs -->", range: opening.upperBound..<page.endIndex)
        else { throw UsageError("\(path) has no block \(block.name)") }
        page.replaceSubrange(opening.upperBound..<closing.lowerBound, with: block.text)
    }
    try page.write(toFile: path, atomically: true, encoding: .utf8)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--update-article" {
    try updateArticle(at: "Sources/TUI/TUI.docc/Articles/EnvironmentVariables.md")
    exit(0)
}
if arguments.contains("--help") || arguments.contains("-h") {
    print(usage, terminator: "")
    exit(0)
}
/// Does what `arguments` ask for.
func run(arguments: [String]) throws {
    let options = try Options(arguments: arguments)
    guard let output = options.output else {
        print(options.text, terminator: "")
        return
    }
    let file = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try options.text.write(to: file, atomically: true, encoding: .utf8)
}

do {
    try run(arguments: arguments)
} catch let error as UsageError {
    FileHandle.standardError.write(Data("error: \(error.message)\n\n\(usage)".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
