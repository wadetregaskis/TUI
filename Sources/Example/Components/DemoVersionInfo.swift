//  🖥️ TUI — A Terminal UI framework for Swift
//  DemoVersionInfo.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUI

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// The TUI version and the system it runs on, right-aligned in two rows:
/// the trailing item of the Example's top bar.
///
/// The bar's leading end is the page's own `.navigationTitle` (and
/// `.navigationSubtitle`), which every page sets; this is what the app adds
/// beside it, once, at its root (`ContentView`).
struct DemoVersionInfo: View {
    var body: some View {
        VStack(alignment: .trailing) {
            Text(verbatim: "TUI v\(tuiKitVersion)")
            Text(verbatim: systemInfo)
        }
        .foregroundStyle(.palette.foregroundTertiary)
    }
}

// MARK: - System Info

extension DemoVersionInfo {
    private var systemInfo: String {
        "\(osName) \(osVersion) · \(architecture)"
    }

    private var osName: String {
        #if os(macOS)
            return "macOS"
        #elseif os(Linux)
            return linuxDistroName
        #else
            return "Unknown"
        #endif
    }

    private var osVersion: String {
        #if os(macOS)
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion)"
        #elseif os(Linux)
            return linuxDistroVersion
        #else
            return ""
        #endif
    }

    private var architecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }
}

// MARK: - Linux Distro Detection

#if os(Linux)
    extension DemoVersionInfo {
        /// Reads a value from /etc/os-release.
        private func osReleaseValue(for key: String) -> String? {
            guard let contents = try? String(contentsOfFile: "/etc/os-release", encoding: .utf8) else {
                return nil
            }
            for line in contents.split(separator: "\n") where line.hasPrefix("\(key)=") {
                let value = line.dropFirst(key.count + 1)
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            return nil
        }

        private var linuxDistroName: String {
            osReleaseValue(for: "NAME") ?? "Linux"
        }

        private var linuxDistroVersion: String {
            osReleaseValue(for: "VERSION_ID") ?? kernelVersion
        }

        private var kernelVersion: String {
            var uts = utsname()
            uname(&uts)
            // The field's own size rather than `SYS_NMLN`, which glibc and
            // Darwin define and musl does not.
            let capacity = MemoryLayout.size(ofValue: uts.release)
            return withUnsafePointer(to: &uts.release) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
        }
    }
#endif
