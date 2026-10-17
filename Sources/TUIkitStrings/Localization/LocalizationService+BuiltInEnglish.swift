//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationService+BuiltInEnglish.swift
//
//  TUIkit's English words, compiled in, for a program that has no resource
//  bundle to read them from.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension LocalizationService {
    /// TUIkit's English words, compiled in: what its own strings read where
    /// its English translation file cannot be read (see ``ModuleResources``).
    ///
    /// Read only then, and parsed once, the first time: a program that can
    /// read `en.json` reads it, as it always has. The other languages are in
    /// the bundle alone, so where it cannot be read a German user reads
    /// English, as for a word German has no translation of.
    static let builtInEnglish: [String: String] = translationTable(from: Data(builtInEnglishJSON.utf8)) ?? [:]

    /// `Localization/translations/en.json`, as it is. A copy, so a key added
    /// there is added here too: `BuiltInEnglishTests` compares the two, and
    /// names every key they disagree on.
    ///
    /// The file's text, read by the parser that reads the file, rather than a
    /// dictionary literal: 5.5 KB in the binary where the literal measured
    /// 8.1 KB (its 144 pairs as 32-byte entries, and their longer strings;
    /// `swiftc -O`, 6.2.4, 2026-10-10).
    private static let builtInEnglishJSON = #"""
    {
      "button.ok": "OK",
      "button.cancel": "Cancel",
      "button.yes": "Yes",
      "button.no": "No",
      "button.save": "Save",
      "button.delete": "Delete",
      "button.close": "Close",
      "button.apply": "Apply",
      "button.reset": "Reset",
      "button.submit": "Submit",
      "button.search": "Search",
      "button.clear": "Clear",
      "button.add": "Add",
      "button.remove": "Remove",
      "button.edit": "Edit",
      "button.done": "Done",
      "button.next": "Next",
      "button.previous": "Previous",
      "button.back": "Back",
      "button.forward": "Forward",
      "button.refresh": "Refresh",
      "button.rename": "Rename",
      "button.paste": "Paste",
      "button.copy": "Copy",
      "button.replace": "Replace",
      "button.replaceAll": "Replace All",

      "label.search": "Search",
      "label.name": "Name",
      "label.description": "Description",
      "label.value": "Value",
      "label.status": "Status",
      "label.error": "Error",
      "label.warning": "Warning",
      "label.info": "Info",
      "label.success": "Success",
      "label.loading": "Loading",
      "label.empty": "Empty",
      "label.position": "Position",
      "label.foreground": "Foreground",
      "label.secondary": "Secondary",
      "label.accent": "Accent",
      "label.border": "Border",
      "label.background": "Background",
      "label.noItems": "No items",
      "label.none": "None",
      "label.page": "Page",
      "label.item": "Item",
      "label.items": "Items",
      "label.total": "Total",
      "label.from": "From",
      "label.to": "To",
      "label.gradient": "Gradient",
      "label.noResults": "No Results",
      "label.noResultsFor": "No Results for '%@'",
      "label.noResultsHint": "Check the spelling or try a new search.",
      "label.suppressDialog": "Do not show this message again",
      "label.find": "Find",
      "label.replaceWith": "Replace with",
      "label.hideColumn": "Hide “%@”",
      "label.showSidebar": "Show Sidebar",
      "label.hideSidebar": "Hide Sidebar",
      "label.showInspector": "Show Inspector",
      "label.hideInspector": "Hide Inspector",
      "label.showContentColumn": "Show Content Column",
      "label.hideContentColumn": "Hide Content Column",
      "label.showNamedPanel": "Show “%@”",
      "label.hideNamedPanel": "Hide “%@”",

      "error.invalid_input": "Invalid input",
      "error.required_field": "This field is required",
      "error.not_found": "Not found",
      "error.access_denied": "Access denied",
      "error.network_error": "Network error",
      "error.unknown": "Unknown error",
      "error.invalid_format": "Invalid format",
      "error.operation_failed": "Operation failed",
      "error.timeout": "Operation timed out",
      "error.file_not_found": "File not found",
      "error.permission_denied": "Permission denied",

      "placeholder.search": "Search...",
      "placeholder.enter_text": "Enter text...",
      "placeholder.enter_value": "Enter value...",
      "placeholder.select_option": "Select an option...",
      "placeholder.enter_name": "Enter name...",
      "placeholder.choose_file": "Choose a file...",

      "menu.file": "File",
      "menu.edit": "Edit",
      "menu.view": "View",
      "menu.help": "Help",
      "menu.new": "New",
      "menu.open": "Open",
      "menu.save": "Save",
      "menu.exit": "Exit",
      "menu.undo": "Undo",
      "menu.redo": "Redo",
      "menu.openLink": "Open Link",
      "menu.copyLink": "Copy Link",
      "menu.copyLinkLabel": "Copy Label",
      "menu.copyLinkAsMarkdown": "Copy as Markdown",

      "statusbar.quit": "quit",
      "statusbar.appearance": "appearance",
      "statusbar.theme": "theme",
      "statusbar.undo": "undo",
      "statusbar.redo": "redo",
      "statusbar.activate": "activate",
      "statusbar.choose": "choose",
      "statusbar.toggle": "toggle",
      "statusbar.open": "open",
      "statusbar.select": "select",
      "statusbar.submit": "submit",
      "statusbar.showColumn": "show column",
      "statusbar.hideColumn": "hide column",
      "statusbar.showSidebar": "show sidebar",
      "statusbar.hideSidebar": "hide sidebar",
      "statusbar.showInspector": "show inspector",
      "statusbar.hideInspector": "hide inspector",
      "statusbar.showContentColumn": "show content column",
      "statusbar.hideContentColumn": "hide content column",
      "statusbar.showNamedPanel": "show %@",
      "statusbar.hideNamedPanel": "hide %@",
      "statusbar.dismiss": "dismiss",
      "statusbar.cancel": "cancel",
      "statusbar.goBack": "go back",
      "statusbar.closePopover": "close popover",
      "statusbar.closeSuggestions": "close suggestions",
      "statusbar.cancelMove": "cancel move",
      "statusbar.clearSelection": "clear selection",
      "statusbar.stopExtendingSelection": "stop extending selection",
      "statusbar.stopEditingColumns": "stop editing columns",
      "statusbar.copied": "Copied",
      "statusbar.sentToTerminalClipboard": "Sent to the terminal's clipboard",
      "statusbar.notCopiedNoClipboard": "Not copied: no clipboard reachable from here",
      "statusbar.notCopiedHelperFailed": "Not copied: the clipboard helper failed",
      "statusbar.pasteWithTerminal": "Nothing to paste here: use the terminal's paste",
      "statusbar.pastedAppCopy": "Pasted this app's last copy: for your clipboard, use the terminal's paste",
      "statusbar.menu.open": "open %@",
      "statusbar.menu.close": "close %@",
      "statusbar.menu.dropDown": "drop-down menu",
      "statusbar.menu.popUp": "menu",

      "dialog.confirm": "Confirm",
      "dialog.delete_confirmation": "Are you sure you want to delete this?",
      "dialog.unsaved_changes": "You have unsaved changes. Do you want to save them?",
      "dialog.overwrite_confirmation": "This file already exists. Do you want to overwrite it?",
      "dialog.exit_confirmation": "Do you want to exit?",
      "dialog.success": "Operation completed successfully",
      "dialog.error": "An error occurred",

      "validation.email_invalid": "Invalid email address",
      "validation.password_too_short": "Password must be at least 8 characters",
      "validation.username_taken": "Username already exists",
      "validation.field_required": "This field cannot be empty",

      "appearance.rounded": "Rounded",
      "appearance.line": "Line",
      "appearance.doubleLine": "Double line",
      "appearance.heavy": "Heavy",
      "appearance.braille": "Braille",
      "appearance.braille2": "Thick Braille",
      "appearance.block": "Block",
      "appearance.blank": "Blank",

      "key.space": "Space",

      "timeSpan.year.wide.one": "%@ year",
      "timeSpan.year.wide.other": "%@ years",
      "timeSpan.year.abbreviated.one": "%@ yr",
      "timeSpan.year.abbreviated.other": "%@ yrs",
      "timeSpan.month.wide.one": "%@ month",
      "timeSpan.month.wide.other": "%@ months",
      "timeSpan.month.abbreviated.one": "%@ mth",
      "timeSpan.month.abbreviated.other": "%@ mths"
    }
    """#
}
