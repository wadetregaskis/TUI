//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextContentType.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - TextContentType

/// Declares the semantic content type of a text field and filters input accordingly.
///
/// In SwiftUI, `NSTextContentType` (`UITextContentType` on iOS) provides
/// autofill hints to the system. In a TUI there is no autofill, so
/// `TextContentType` instead defines an **allowed character set** for input
/// filtering. Typed characters and pasted text are filtered against the
/// allowed set, in a `TextField`, a `SecureField` and a `TextEditor` alike: a
/// character that could not be part of a valid value is dropped, and the
/// terminal's bell rings — once for a paste, however many it drops — so input
/// is never refused in silence. Each set admits every character a valid value
/// may hold, not just the common ones, and a type whose values are free text
/// (a name, an address, a date written out) filters nothing.
///
/// Every `NSTextContentType` member is here under its Swift name, so
/// `.textContentType(.URL)` and the rest compile as written. `integer` and
/// `decimal` are TUIkit's own.
///
/// ## Usage
///
/// ```swift
/// // Only allow URL-valid characters
/// TextField("URL", text: $url)
///     .textContentType(.URL)
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
/// | Type                                   | Allowed Characters                         |
/// |----------------------------------------|--------------------------------------------|
/// | `URL`                                  | Alphanumeric, `:/.?#[]@!$&'()*+,;=-_~%`    |
/// | `emailAddress`                         | Alphanumeric, `@.` and ``!#$%&'*+-/=?^_`{|}~`` |
/// | `telephoneNumber`                      | `0-9`, `+()-./ #*`, space                  |
/// | `username`                             | Alphanumeric, `._-@`                       |
/// | `oneTimeCode`, `creditCardSecurityCode`, `creditCardExpirationMonth`, `creditCardExpirationYear`, `birthdateDay`, `birthdateYear` | `0-9` |
/// | `creditCardNumber`                     | `0-9`, space, `-`                          |
/// | `creditCardExpiration`                 | `0-9`, `/-.`, space                        |
/// | `postalCode`, `shipmentTrackingNumber`, `flightNumber` | Alphanumeric, space, `-`   |
/// | `birthdateMonth`                       | Alphanumeric, `.`                          |
/// | `integer`                              | `0-9`, `+-`                                |
/// | `decimal`                              | `0-9`, `+-`, `.,`                          |
/// | Everything else: `password`, `newPassword`, the names, the address parts, `jobTitle`, `organizationName`, `location`, `countryName`, the card holder's names, `creditCardType`, `dateTime`, `birthdate` | All characters (no filtering) |
///
/// "Alphanumeric" is Unicode's letters and digits, so an internationalised
/// address or URL (RFC 6531, RFC 3987), or a postal code in any script, is
/// admitted.
public enum TextContentType: Sendable, Equatable {
    /// URL input. Allows alphanumeric characters and URL-safe punctuation.
    case URL

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

    /// A new password, as when signing up or changing one. Allows all
    /// characters (no filtering).
    case newPassword

    /// One-time code input. Allows digits only.
    case oneTimeCode

    // MARK: Names

    /// A full name. Free text.
    case name

    /// A prefix or title, such as "Dr.". Free text.
    case namePrefix

    /// A given name. Free text.
    case givenName

    /// A middle name. Free text.
    case middleName

    /// A family name. Free text.
    case familyName

    /// A suffix, such as "Jr.". Free text.
    case nameSuffix

    /// A nickname. Free text.
    case nickname

    /// A job title. Free text.
    case jobTitle

    /// An organisation's name. Free text.
    case organizationName

    // MARK: Places

    /// A location, such as a point of interest or an address. Free text.
    case location

    /// A full street address, which may run over several lines. Free text.
    case fullStreetAddress

    /// The first line of a street address. Free text.
    case streetAddressLine1

    /// The second line of a street address. Free text.
    case streetAddressLine2

    /// A city. Free text.
    case addressCity

    /// A state or province. Free text.
    case addressState

    /// A city and a state or province together. Free text.
    case addressCityAndState

    /// A sublocality, such as a district. Free text.
    case sublocality

    /// A country or region. Free text.
    case countryName

    /// A postal code. Allows alphanumeric characters, space and `-`: postal
    /// codes are digits in some countries and letters and digits in others
    /// (`SW1A 1AA`, `K1A 0B1`, `1234 AB`, `00-950`).
    case postalCode

    // MARK: Payment

    /// A credit card number. Allows digits, and the spaces and hyphens a
    /// number is grouped with.
    case creditCardNumber

    /// The name on a credit card. Free text.
    case creditCardName

    /// The given name on a credit card. Free text.
    case creditCardGivenName

    /// The middle name on a credit card. Free text.
    case creditCardMiddleName

    /// The family name on a credit card. Free text.
    case creditCardFamilyName

    /// A card's security code. Allows digits only.
    case creditCardSecurityCode

    /// A card's expiration date. Allows digits and the separators a date is
    /// written with: `/`, `-`, `.` and space.
    case creditCardExpiration

    /// A card's expiration month. Allows digits only.
    case creditCardExpirationMonth

    /// A card's expiration year. Allows digits only.
    case creditCardExpirationYear

    /// A card's type, such as "Visa". Free text.
    case creditCardType

    // MARK: Other

    /// A shipment tracking number. Allows alphanumeric characters, space and
    /// `-`.
    case shipmentTrackingNumber

    /// A flight number, such as `QF 1`. Allows alphanumeric characters, space
    /// and `-`.
    case flightNumber

    /// A date, a time or both, which may be written out ("tomorrow at 3").
    /// Free text.
    case dateTime

    /// A full birth date, which may be written with a month's name. Free text.
    case birthdate

    /// The day of a birth date. Allows digits only.
    case birthdateDay

    /// The month of a birth date, as a number or a name. Allows alphanumeric
    /// characters and the `.` of an abbreviation.
    case birthdateMonth

    /// The year of a birth date. Allows digits only.
    case birthdateYear

    // MARK: TUIkit's own

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
    /// `nil` for a type whose values are free text — `.password`, a name, an
    /// address — to indicate no filtering.
    public var allowedCharacters: CharacterSet? {
        switch self {
        case .URL: Self.urlCharacters
        case .emailAddress: Self.emailCharacters
        case .telephoneNumber: Self.phoneCharacters
        case .username: Self.usernameCharacters
        case .oneTimeCode, .creditCardSecurityCode, .creditCardExpirationMonth, .creditCardExpirationYear,
            .birthdateDay, .birthdateYear:
            Self.digitCharacters
        case .creditCardNumber: Self.cardNumberCharacters
        case .creditCardExpiration: Self.writtenDateCharacters
        case .postalCode, .shipmentTrackingNumber, .flightNumber: Self.codeCharacters
        case .birthdateMonth: Self.monthCharacters
        case .integer: Self.integerCharacters
        case .decimal: Self.decimalCharacters
        // Free text: every character may be part of a valid value.
        case .password, .newPassword, .name, .namePrefix, .givenName, .middleName, .familyName, .nameSuffix,
            .nickname, .jobTitle, .organizationName, .location, .fullStreetAddress, .streetAddressLine1,
            .streetAddressLine2, .addressCity, .addressState, .addressCityAndState, .sublocality, .countryName,
            .creditCardName, .creditCardGivenName, .creditCardMiddleName, .creditCardFamilyName, .creditCardType,
            .dateTime, .birthdate:
            nil
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

    /// A card number's characters: digits, and the space or hyphen its groups
    /// are written with.
    fileprivate static let cardNumberCharacters = CharacterSet(charactersIn: "0123456789 -")

    /// A date written in digits: `12/27`, `12-2027`, `12.27`, `12 27`.
    fileprivate static let writtenDateCharacters = CharacterSet(charactersIn: "0123456789/-. ")

    /// A code made of letters and digits in groups: a postal code, a tracking
    /// number, a flight number.
    fileprivate static let codeCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: " -")
        return set
    }()

    /// A month, as a number or a name, abbreviated or not.
    fileprivate static let monthCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: ".")
        return set
    }()
}
