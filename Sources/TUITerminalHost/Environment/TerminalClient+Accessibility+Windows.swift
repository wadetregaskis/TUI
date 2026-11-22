//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalClient+Accessibility+Windows.swift
//
//  Windows's own accessibility settings, as the host's answer to
//  `TerminalClient.hostAccessibility()`.
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(Windows)
import WinSDK
#endif

extension TerminalClient {
    /// Windows's answer, from its three settings that have a counterpart here
    /// (Settings ▸ Accessibility): Animation effects off is reduced motion,
    /// Transparency effects off reduced transparency, and a contrast theme
    /// increased contrast. Windows has nothing for differentiating without
    /// colour. `nil` when none of the three could be read.
    ///
    /// - Parameters:
    ///   - animates: `SPI_GETCLIENTAREAANIMATION`, or `nil` where it could not
    ///     be read.
    ///   - transparent: `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`'s
    ///     `EnableTransparency` as a switch, or `nil` where it is not set.
    ///   - highContrast: Whether `SPI_GETHIGHCONTRAST` has
    ///     `HCF_HIGHCONTRASTON`, or `nil` where it could not be read.
    static func windowsAccessibility(animates: Bool?, transparent: Bool?, highContrast: Bool?)
        -> AccessibilityPreferences?
    {
        guard animates != nil || transparent != nil || highContrast != nil else { return nil }
        var on: AccessibilityPreferences = []
        if animates == false { on.insert(.reduceMotion) }
        if transparent == false { on.insert(.reduceTransparency) }
        if highContrast == true { on.insert(.increaseContrast) }
        return on
    }

    #if os(Windows)
        /// Reads the three settings ``windowsAccessibility(animates:transparent:highContrast:)``
        /// maps: two `SystemParametersInfoW` queries and one registry value,
        /// none of which starts a process. Measured 2026-11-20 on Windows 11
        /// build 26300 with each at its default: animations on
        /// (`SPI_GETCLIENTAREAANIMATION` 1), transparency on
        /// (`EnableTransparency` 1), no contrast theme (`HIGHCONTRASTW`'s flags
        /// 0x7E, without `HCF_HIGHCONTRASTON`).
        static func readWindowsAccessibility() -> AccessibilityPreferences? {
            var animates: WindowsBool = false
            let animatesRead = unsafe SystemParametersInfoW(UINT(SPI_GETCLIENTAREAANIMATION), 0, &animates, 0)

            var contrast = unsafe HIGHCONTRASTW()
            unsafe contrast.cbSize = UINT(MemoryLayout<HIGHCONTRASTW>.size)
            let contrastRead = unsafe SystemParametersInfoW(UINT(SPI_GETHIGHCONTRAST), contrast.cbSize, &contrast, 0)

            // HKEY_CURRENT_USER is `(HKEY)(ULONG_PTR)((LONG)0x80000001)`, a
            // macro Swift does not import: the LONG sign-extends.
            let currentUser = unsafe HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0001)))
            var transparency: DWORD = 0
            var size = DWORD(MemoryLayout<DWORD>.size)
            let key = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
            let status = key.withCString(encodedAs: UTF16.self) { key in
                "EnableTransparency".withCString(encodedAs: UTF16.self) { value in
                    unsafe RegGetValueW(currentUser, key, value, DWORD(RRF_RT_REG_DWORD), nil, &transparency, &size)
                }
            }

            return unsafe windowsAccessibility(
                animates: animatesRead ? animates.boolValue : nil,
                transparent: status == ERROR_SUCCESS ? transparency != 0 : nil,
                highContrast: contrastRead ? contrast.dwFlags & DWORD(HCF_HIGHCONTRASTON) != 0 : nil)
        }
    #endif
}
