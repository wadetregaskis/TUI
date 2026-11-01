#!/usr/bin/env python3
"""Counts every `@unchecked Sendable` and `nonisolated(unsafe)` in the sources, by the reason it is there.

The classes are assigned by the declaration's name, by hand, as of 2026-11, so new declarations come out UNCLASSIFIED:
that is the list to read, and to add to the tables below. Comments are not counted.
"""
import os
import re
import sys

UNCHECKED = {
 'U-tool: in Example or Stress, not shipped framework': r'LinkOpenLog|APIClassRow|StressClock',
 'U-lock: state really behind a lock/condition; the unchecked is the wrapper': r'class Lock<|LifecycleManager|NotificationService|AnimationCompletion:|CustomAnimationCurve|struct Table|struct Registry|JSONFileStorage|UserDefaultsStorage|RunState|LoadedData|LoadedTexts|DepartedUndoSteps|TerminalWriteGate|StallWatchdog|SearchIndexHandle|final class Store|URLImageCache|URLTaskHandle|LightDarkColorTable|ObjectHub|LocalizationService|ClipboardWriter|BodyMutationDiagnostic',
 'U-immutable: every field a let, of a type the compiler cannot see is Sendable': r'final class SearchIndex:|class Box: Equatable|LocalizedTextSource|_DecodedImage|DropPayload|_AnyTransitionBox|TransactionExtras',
 'U-service: per-app or per-frame service, main thread only, no lock': r'TUIContext|FocusManager|KeyEventDispatcher|MouseEventDispatcher|StatusBarState|WindowChromeState|TooltipState|TerminalBell|KeysAfterFrame|ScreenSelection|DragAndDropSession|ToolbarCustomizationGestures|ModifierKeyMonitor|KeyboardShortcutRegistry|GeometryCoordinator|MatchedGeometryRegistry|GeometryAsk|TerminalImageStore|TypedClipboard|AppUndoKeys|ScrollToRegistry|ThemeManager|AnimationStore|AnimationCompletionTracker|DepartureStore|PlacementStore|class StateStorage|class RenderCache|PreferenceStorage|VolatileReadTracker|class Link:|class Registration|LinkActivationGate|SettleWork|StateBox',
 'U-box: mutable box a render refreshes and an event closure reads, main thread only': r'class Box: @unchecked|MenuOpenAction|ButtonKeyExtras|class Action|AssignedFocusID|FocusHandoffOffer|PreferredFocusOffer|KeyboardShortcutAssignment|RegionOrigin|PointerSpaceOrigin|DropDelegateState|ScrollContentReply|LastFocusedIDBox|LastInteractionGenBox|LastViewportBox|OutlineActivation|OutlineSubtreeIndex|SearchSelectionBox|TextUndoStep',
 'U-payload: value carrying a closure, AnyHashable, existential or generic the compiler cannot prove Sendable': r'EnvironmentValues|PreferenceValues|StyleChain|InstalledPrimitiveButtonStyle|ComparableStyle|AnyTextRenderer|TextAttributes|DismissMenuAction|SubmitActionEntry|RenameAction|StatusBarItem|GlassNamespacedID|AccessoryBarID|CustomDetent|URLEnabled|FileDialogItemViews|HandedItem|TransferableExport|MainActorUndoManager|StorageFailure|FormattedTimeSource|GestureState',
}
NONISOLATED = {
 'N-signal: read by an async-signal handler; no lock is allowed there': r'FatalSignalTerminalRestore',
 'N-flag: process-wide capability or generation, written at startup or between frames, read anywhere': r'processCurrent|processCap|processSupported|processHairlineSupported|processCompressionSupported|processPictureUnderTextSupported|generation|_isEnabled',
 'N-memo: process-wide memo of a pure function or asset table, used from the render path': r'pulseRampCache|rampCache|RampCache|quantiseCache|cache:|ansi16Built|decoded:|pictures:|colors:|colorLookups|entries:|names:|static var shared = Store|noted',
 'N-default: immutable EnvironmentKey default of a non-Sendable type': r'defaultValue',
 'N-exempt: a public static the project rules exempt from No Singletons': r'NotificationService|backend: StorageBackend|static var current',
 'N-local: a local let carried across a closure the compiler thinks may leave the thread': r'nonisolated\(unsafe\) let [a-z]+ =',
 'N-field: an immutable stored field of a non-Sendable type': r'private let parents|let value: AnyHashable',
}


def find_sites(sources):
    sites = []
    for directory, _, files in os.walk(sources):
        for name in files:
            if not name.endswith('.swift'):
                continue
            path = os.path.join(directory, name)
            with open(path, errors='replace') as source:
                for number, line in enumerate(source, 1):
                    text = line.strip()
                    if text.startswith(('//', '*')):
                        continue
                    if '@unchecked Sendable' in line:
                        sites.append(('unchecked', os.path.relpath(path, sources), number, text))
                    elif 'nonisolated(unsafe)' in line:
                        sites.append(('nonisolated', os.path.relpath(path, sources), number, text))
    return sorted(sites)


def classify(site):
    kind, path, _, text = site
    table = UNCHECKED if kind == 'unchecked' else NONISOLATED
    by_text = [name for name, pattern in table.items() if re.search(pattern, text)]
    by_path = [name for name, pattern in table.items() if re.search(pattern, path)]
    # The table's order decides between several: signal-handler state first, and so on.
    hits = by_text or by_path
    return hits[0] if hits else None


def main(sources, listing=False):
    sites = find_sites(sources)
    classes = {}
    for site in sites:
        classes.setdefault(classify(site), []).append(site)
    print(f"{sum(s[0] == 'unchecked' for s in sites)} @unchecked Sendable, {sum(s[0] == 'nonisolated' for s in sites)} nonisolated(unsafe)")
    for name in list(UNCHECKED) + list(NONISOLATED) + [None]:
        found = classes.get(name, [])
        if name is None and not found:
            continue
        print(f"{len(found):4d}  {name or 'UNCLASSIFIED'}")
        if listing or name is None:
            for _, path, number, text in found:
                print(f'        {path}:{number}  {text[:90]}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'Sources'),
         '--list' in sys.argv)
