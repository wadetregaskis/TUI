//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextContentTypeTests.swift
//
//  `TextContentType` had zero coverage: no test in any target so much as
//  named it, so `allowedCharacters`, `isAllowed`, `filterString` and all
//  seven character-set tables were unreachable from the suite. The tables are
//  the whole API — in a terminal there is no autofill, so the content type IS
//  the filter — and the doc comment's table is what an app is written against.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

@Suite("Text content type filtering")
struct TextContentTypeTests {

    /// The doc comment's own table, one row per case.
    @Test(
        "Each type keeps exactly the characters it documents",
        arguments: [
            (TextContentType.URL, "http://a.com/x y<>", "http://a.com/xy"),
            // `!` is RFC 5322 `atext`; a space and a comma are not.
            (.emailAddress, "a b@c!.d+e-f_g,", "ab@c!.d+e-f_g"),
            (.telephoneNumber, "+1 (555) 123-4567 ext#9*", "+1 (555) 123-4567 #9*"),
            (.username, "us er!na.me-1@x", "userna.me-1@x"),
            (.oneTimeCode, "12ab34", "1234"),
            (.integer, "a-1b2", "-12"),
            (.decimal, "1a.5-x", "1.5-"),
            (.creditCardNumber, "4111 1111-x1111", "4111 1111-1111"),
            (.creditCardSecurityCode, "12a3", "123"),
            (.creditCardExpiration, "12/27 (exp)", "12/27 "),
            (.postalCode, "SW1A 1AA!", "SW1A 1AA"),
            (.shipmentTrackingNumber, "1Z 999-AA1#", "1Z 999-AA1"),
            (.flightNumber, "QF 1!", "QF 1"),
            (.birthdateMonth, "Sept.,", "Sept."),
            (.birthdateYear, "1990s", "1990"),
        ])
    func filterKeepsTheDocumentedSet(
        type: TextContentType, input: String, expected: String
    ) {
        #expect(type.filterString(input) == expected)
    }

    @Test("Password filters nothing at all")
    func passwordIsUnfiltered() {
        // `nil` allowed-set is the signal, and both readers must honour it:
        // a password may contain anything, including what every other type
        // strips.
        #expect(TextContentType.password.allowedCharacters == nil)
        let awkward = "p@$$ w0rd!<>🙂"
        #expect(TextContentType.password.filterString(awkward) == awkward)
        #expect(awkward.allSatisfy { TextContentType.password.isAllowed($0) })
    }

    @Test(
        "A type whose values are free text filters nothing",
        arguments: [
            TextContentType.newPassword, .name, .namePrefix, .givenName, .middleName, .familyName, .nameSuffix,
            .nickname, .jobTitle, .organizationName, .location, .fullStreetAddress, .streetAddressLine1,
            .streetAddressLine2, .addressCity, .addressState, .addressCityAndState, .sublocality, .countryName,
            .creditCardName, .creditCardGivenName, .creditCardMiddleName, .creditCardFamilyName, .creditCardType,
            .dateTime, .birthdate,
        ])
    func freeTextIsUnfiltered(type: TextContentType) {
        #expect(type.allowedCharacters == nil, "\(type)")
        let anything = "Zoë O'Brien-Smith, 3rd · 東京 🙂"
        #expect(type.filterString(anything) == anything)
    }

    @Test("Every other type has a set", arguments: [
        TextContentType.URL, .emailAddress, .telephoneNumber, .username,
        .oneTimeCode, .integer, .decimal, .creditCardNumber, .creditCardSecurityCode, .creditCardExpiration,
        .creditCardExpirationMonth, .creditCardExpirationYear, .postalCode, .shipmentTrackingNumber,
        .flightNumber, .birthdateDay, .birthdateMonth, .birthdateYear,
    ])
    func everyOtherTypeFilters(type: TextContentType) {
        #expect(type.allowedCharacters != nil, "\(type)")
    }

    @Test("isAllowed answers per character, and a rejected one is dropped silently")
    func perCharacterFilter() {
        #expect(TextContentType.oneTimeCode.isAllowed("5"))
        #expect(!TextContentType.oneTimeCode.isAllowed("a"))
        #expect(TextContentType.integer.isAllowed("-"))
        #expect(!TextContentType.integer.isAllowed("."))
        #expect(TextContentType.decimal.isAllowed("."))
    }

    @Test("A character is allowed only if EVERY scalar in it is")
    func multiScalarCharacters() {
        // `isAllowed` takes a `Character`, which can be several scalars. An
        // emoji is one Character and no alphanumeric set contains it, so a
        // username field drops it whole rather than keeping half of it.
        #expect(!TextContentType.username.isAllowed("🙂"))
        #expect(TextContentType.username.filterString("bob🙂smith") == "bobsmith")
    }

    @Test("Filtering everything out yields an empty string, not the input")
    func fullyRejectedInput() {
        // What the paste path's `guard !sanitized.isEmpty` is protecting
        // against: a paste of nothing usable must insert nothing, not
        // everything.
        #expect(TextContentType.oneTimeCode.filterString("abc").isEmpty)
    }
}
