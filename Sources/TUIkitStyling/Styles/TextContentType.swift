//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextContentType.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - TextContentType

/// Declares the semantic content type of a text field and filters input accordingly.
///
/// In SwiftUI, `UITextContentType` provides autofill hints to the system.
/// In a TUI there is no autofill, so `TextContentType` instead defines an
/// **allowed character set** for input filtering. Both typed characters and
/// pasted text are filtered against the allowed set: a character that could
/// not be part of a valid value is dropped, and the terminal's bell rings —
/// once for a paste, however many it drops — so input is never refused in
/// silence. Each set admits every character a valid value may hold, not just
/// the common ones.
///
/// ## Usage
///
/// ```swift
/// // Only allow URL-valid characters
/// TextField("URL", text: $url)
///     .textContentType(.url)
///
/// // Only allow digits
/// TextField("Code", text: $code)
///     .textContentType(.oneTimeCode)
///
/// // Apply to all fields in a container
/// VStack {
///     TextField("User", text: $user)
///     SecureField("Password", text: $pass)
/// }
/// .textContentType(.username)
/// ```
///
/// ## Character Filtering
///
/// | Type              | Allowed Characters                            |
/// |-------------------|-----------------------------------------------|
/// | `url`             | Alphanumeric, `:/.?#[]@!$&'()*+,;=-_~%`       |
/// | `emailAddress`    | Alphanumeric, `@.` and ``!#$%&'*+-/=?^_`{|}~`` |
/// | `telephoneNumber` | `0-9`, `+()-./ #*`, space                     |
/// | `username`        | Alphanumeric, `._-@`                          |
/// | `password`        | All characters (no filtering)                 |
/// | `oneTimeCode`     | `0-9`                                         |
/// | `integer`         | `0-9`, `+-`                                   |
/// | `decimal`         | `0-9`, `+-`, `.,`                             |
///
/// "Alphanumeric" is Unicode's letters and digits, so an internationalised
/// address or URL (RFC 6531, RFC 3987) is admitted.
public enum TextContentType: Sendable, Equatable {
    /// URL input. Allows alphanumeric characters and URL-safe punctuation.
    case url

    /// Email address input. Allows alphanumeric characters, `@`, `.`, and the
    /// rest of what RFC 5322 lets an unquoted local part hold:
    /// `!#$%&'*+-/=?^_{|}~` and the backtick.
    case emailAddress

    /// Telephone number input. Allows digits, `+`, `(`, `)`, `-`, `.`, `/`, `#`, `*`, space.
    case telephoneNumber

    /// Username input. Allows alphanumeric characters, `.`, `_`, `-`, `@`.
    case username

    /// Password input. Allows all characters (no filtering).
    case password

    /// One-time code input. Allows digits only.
    case oneTimeCode

    /// Integer input. Allows digits and a sign, `+` or `-`.
    case integer

    /// Decimal number input. Allows digits, a sign, and `.` or `,` for the
    /// fractional part, whichever the user's locale writes.
    case decimal
}

// MARK: - Character Filtering

extension TextContentType {
    /// The set of Unicode scalars allowed for this content type.
    ///
    /// `.password` returns `nil` to indicate no filtering.
    public var allowedCharacters: CharacterSet? {
        switch self {
        case .url:
            return Self.urlCharacters
        case .emailAddress:
            return Self.emailCharacters
        case .telephoneNumber:
            return Self.phoneCharacters
        case .username:
            return Self.usernameCharacters
        case .password:
            return nil
        case .oneTimeCode:
            return Self.digitCharacters
        case .integer:
            return Self.integerCharacters
        case .decimal:
            return Self.decimalCharacters
        }
    }

    /// Whether the given character is allowed by this content type.
    ///
    /// - Parameter character: The character to check.
    /// - Returns: `true` if the character passes the filter, or if this type
    ///   has no filter (`.password`).
    public func isAllowed(_ character: Character) -> Bool {
        guard let allowed = allowedCharacters else { return true }
        return character.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Filters a string, keeping only characters allowed by this content type.
    ///
    /// - Parameter string: The input string to filter.
    /// - Returns: A new string containing only the allowed characters.
    public func filterString(_ string: String) -> String {
        guard allowedCharacters != nil else { return string }
        return String(string.filter { isAllowed($0) })
    }
}

// MARK: - Character Set Definitions

extension TextContentType {
    /// URL-safe characters per RFC 3986.
    fileprivate static let urlCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: ":/.?#[]@!$&'()*+,;=-_~%")
        return set
    }()

    /// Email address characters: RFC 5322's `atext` (what an unquoted local
    /// part may hold), the `.` between its atoms, and the `@`. A domain's
    /// letters, digits, `-` and `.` are among them. A quoted local part
    /// (`"a b"@example.com`) or a domain literal (`user@[192.0.2.1]`) is not
    /// admitted: valid, but not what anyone types into an address field.
    fileprivate static let emailCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "!#$%&'*+-/=?^_`{|}~.@")
        return set
    }()

    /// Telephone number characters: digits, the international prefix, the
    /// keypad's `#` and `*`, and the separators numbers are written with —
    /// RFC 3966's visual separators `-.()`, a space, and the `/` of national
    /// formats (`030/123456`).
    fileprivate static let phoneCharacters: CharacterSet = {
        var set = CharacterSet(charactersIn: "0123456789")
        set.insert(charactersIn: "+()-./ #*")
        set.insert(charactersIn: " ")
        return set
    }()

    /// Username characters.
    fileprivate static let usernameCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "._-@")
        return set
    }()

    /// Digits only.
    fileprivate static let digitCharacters = CharacterSet(charactersIn: "0123456789")

    /// Integer characters: digits and a sign.
    fileprivate static let integerCharacters = CharacterSet(charactersIn: "0123456789+-")

    /// Decimal characters: digits, a sign, and either decimal separator — `.`,
    /// or the `,` that German, French and most of Europe write.
    fileprivate static let decimalCharacters = CharacterSet(charactersIn: "0123456789+-.,")
}
