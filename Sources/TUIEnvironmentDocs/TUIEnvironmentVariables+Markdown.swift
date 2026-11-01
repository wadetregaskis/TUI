//  🖥️ TUI — A Terminal UI framework for Swift
//  TUIEnvironmentVariables+Markdown.swift
//
//  The table as Markdown: for an app's README or website, and for the tables in
//  TUI's own documentation, which a test holds to what this returns.
//
//  Created by Wade Tregaskis
//  License: MIT

extension TUIEnvironmentVariables {
    /// The variables for `audience`, as Markdown: a short introduction, and a
    /// table of each topic under a heading.
    ///
    /// - Parameters:
    ///   - audience: Whose variables. By default, those for the person running the app.
    ///   - headingLevel: The level of each topic's heading: 3 for `###`.
    /// - Returns: The text, ending in a newline.
    public static func markdownSection(
        audience: TUIEnvironmentVariable.Audience = .endUser, headingLevel: Int = 3
    ) -> String {
        introduction(for: audience) + "\n\n" + markdownTables(audience: audience, headingLevel: headingLevel)
    }

    /// `markdownSection(audience:headingLevel:)` without its introduction: what TUI's
    /// own page has under the words it says for itself.
    package static func markdownTables(audience: TUIEnvironmentVariable.Audience, headingLevel: Int = 3) -> String {
        let heading = String(repeating: "#", count: max(1, headingLevel))
        let topics = grouped(variables(for: audience)).map { group in
            var text = "\(heading) \(group.topic.title)\n\n"
            if audience == .detected {
                text += "| Variable | What it says |\n|---|---|\n"
                for variable in group.variables {
                    text += "| `\(variable.name)` | \(variable.effect) |\n"
                }
            } else {
                text += "| Variable | Values | Effect |\n|---|---|---|\n"
                for variable in group.variables {
                    text += "| `\(variable.name)` | \(variable.values) | \(variable.effect) |\n"
                }
            }
            return text
        }
        return topics.joined(separator: "\n")
    }

    /// One table of what code can do about each variable that it can be asked
    /// about, for the page's section on which setting wins.
    package static func markdownCodeSettings() -> String {
        var text = "| Variable | Code | What code can do | Read |\n|---|---|---|---|\n"
        for variable in all where variable.audience != .detected {
            let answer: String
            switch variable.codeSetting {
            case .overrides: answer = "Wins"
            case .cannotOverride: answer = "Can't undo it"
            case .none: answer = "No setting"
            }
            let reading = variable.reading == .once ? "Once" : "Each use"
            text += "| `\(variable.name)` | \(answer) | \(variable.codeSetting.explanation ?? "The variable is the only way.") | \(reading) |\n"
        }
        return text
    }
}
