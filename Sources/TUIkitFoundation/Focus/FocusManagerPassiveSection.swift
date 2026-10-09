//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManagerPassiveSection.swift
//
//  Passive focus sections: the window's toolbars, which Tab reaches after the
//  page and which never take the keyboard by themselves.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// Registers a PASSIVE section: one Tab reaches after the page's, that
    /// never takes the keyboard by itself — not when it is the first section
    /// registered, and not by auto-focusing a control in it. The window's
    /// toolbars.
    ///
    /// Re-register it every render while it applies, as any section.
    ///
    /// ## Why a section of its own kind
    ///
    /// A bar's section used to be registered as a plain one, marked focus-
    /// optional so nothing in it was auto-focused. But a section registered
    /// while no section is active takes the keyboard, so on a frame whose page
    /// registered nothing — a `ProgressView` while a `List` loads — the bottom
    /// bar's section did. The list that arrived later registered into a
    /// section that was not the active one, so it was not auto-focused, and the
    /// optional bar section was not either: nothing held the focus and the
    /// arrows did nothing until Tab.
    ///
    /// So a passive section is never auto-activated
    /// (``registerSection(id:)``); a control registering while one holds the
    /// keyboard with nothing focused takes the keyboard for its own section
    /// (``register(_:inSection:)``); and the end of a pass hands it back the
    /// same way when the bar's focused control has gone
    /// (``idlePassiveHandBackSection()``).
    ///
    /// The mark is NOT cleared per pass, unlike the focus-optional one: the
    /// page registers before the bars are drawn, and is what has to know, as
    /// it registers, that the section holding the keyboard is only a bar. The
    /// ids name the window's two bars whatever is in them, so it never goes
    /// stale.
    package func registerPassiveSection(id: String) {
        passiveSectionIDs.insert(id)
        markSectionFocusOptional(id: id)
        registerSection(id: id)
    }

    /// Whether the active section is passive and holds no focus, so the next
    /// section with something to focus should have the keyboard instead.
    var activeSectionIsIdlePassive: Bool {
        guard currentFocusedID == nil, let activeID = activeSectionIdentifier else { return false }
        return passiveSectionIDs.contains(activeID)
    }

    /// Where the end of a pass moves the keyboard from an idle passive section:
    /// the first section with something to focus, for the auto-focus that
    /// follows to focus it; `nil` when the active section is not an idle
    /// passive one, or nothing else has anything to focus.
    func idlePassiveHandBackSection() -> String? {
        guard activeSectionIsIdlePassive else { return nil }
        return sectionIDs.first { id in
            !passiveSectionIDs.contains(id)
                && section(id: id)?.focusables.contains(where: \.canBeFocused) == true
        }
    }
}
