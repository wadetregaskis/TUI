//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizationService+RunningApps.swift
//
//  The apps a change of language, or of the strings an app registered,
//  reaches — wherever the change was made.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The Apps a Change Reaches

extension LocalizationService {
    /// Notes that `app` runs from this service until ``noteStopped(_:)``: a
    /// change of language or of the strings registered asks it for a frame,
    /// wherever the change was made.
    ///
    /// The service is the process's, and so is what it holds: every app reads
    /// the same language and the same strings. A change to it is made with no
    /// view in hand, and often outside every app's work — `setLanguage(_:)`
    /// from a queue of the app's own, translations registered from a
    /// download's callback — where there is no app whose work it is
    /// (`AmbientApp`) to ask. Asked of that app alone, such a change asked no
    /// app: the screen kept the old strings until something else drew, and a
    /// memoized row kept them past that, the registration's cache clear never
    /// asked. So an app's run loop notes its app here for the length of its
    /// run (`AppRunner`), as a notification host notes the app it draws for.
    ///
    /// Only a RUNNING app is noted. A headless app — a test's — is driven
    /// frame by frame, and reached through its own events and frames, which
    /// are its work. Noting every context that draws, as a notification host
    /// does, would have every test's registration into this one service clear
    /// the render cache of every other test's app drawing beside it.
    package func noteRunning(_ app: any AppRenderState) {
        runningApps.withLock { $0.append(app) }
    }

    /// Notes that `app`'s run has ended: no change asks it for a frame from
    /// here on.
    package func noteStopped(_ app: any AppRenderState) {
        runningApps.withLock { apps in apps.removeAll { $0 === app } }
    }

    /// The apps a change of what this service holds asks for a frame, once
    /// each: every app running from it (``noteRunning(_:)``), and the app
    /// whose work made the change (`AmbientApp`) — a headless app's, which
    /// nothing runs.
    package var appsShowingChanges: [any AppRenderState] {
        var apps = runningApps.withLock { $0 }
        if let ambient = AmbientApp.renderState, !apps.contains(where: { $0 === ambient }) {
            apps.append(ambient)
        }
        return apps
    }
}
