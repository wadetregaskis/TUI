#!/usr/bin/env bash
#
# validate-package-manifest.sh — reject manifest constructs that make this
# package impossible to depend on.
#
# SwiftPM refuses to RESOLVE a versioned dependency that depends on a local
# filesystem path, or that pins another package to a branch or a revision
# rather than a version. The refusal happens in the CONSUMER's resolution, not
# in ours — so a manifest carrying either builds here, passes every test here,
# ships a green CI here, and is simply undownloadable by anyone else. There is
# no other detector: nothing we build in-tree ever exercises the constraint.
#
# `unsafeFlags` used to be a third such construct. SwiftPM 6.2 lifted that
# refusal (swift-package-manager #8896, in 6.2 as #8914; measured with a
# dependency resolved by version on 6.2.4, 6.3.3, 6.4.0 and Xcode 26.3), and
# this package needs 6.2. What is checked now is what such a flag may reach:
#
#   - In a LINKER setting, only `-Xlinker -unexported_symbol -Xlinker
#     '_$s<length><module>*'`, where <module> is one of this package's
#     targets named TUIkit…: Package.swift's `UnexportTUIkitSymbols`. A
#     package's linker flags land on the app's own final link and change the
#     developer's whole program: `-deduplicate` changes which of the app's own
#     key paths compare equal, and a strip flag strips the app's symbols.
#     Those are the developer's to choose; the README offers them, with what
#     each costs. That pattern matches only symbols Swift names under a
#     TUIkit module, and takes them out of what the link exports: TUIkit's
#     own, and the app's own extensions of TUIkit's types and protocols,
#     which Swift names after the extended type's module (Package.swift's
#     trait comment says what that costs a developer's dynamic library and
#     plugins). A trait of its own turns it off.
#   - Any flag only behind a trait. A compile flag reaches every client's
#     build of TUIkit, and no compiler flag undoes another; a link flag has
#     no counter-flag either. So the trait is the client's only way to turn
#     one off (`traits: []`). Package.swift's `DeadStripUnusedAPI` and
#     `UnexportTUIkitSymbols` are the ones there are.
#
# A flag reached for to chase a profiling question, and left in, is the
# realistic way an ungated one arrives.
#
# This is the cheap half of the consumer gate — milliseconds, every push. The
# expensive half (Tools/verify-versioned-consumer.sh) actually resolves and
# builds the package as a dependency, and runs only on tags.
#
# Usage:
#   Tools/validate-package-manifest.sh
#   Tools/validate-package-manifest.sh --self-test   # prove the checks bite
#
# Exit status: 0 if the manifest is consumable, 1 otherwise.
#
# Reads `swift package dump-package` rather than the manifest source. The JSON
# is what SwiftPM itself resolved the manifest to, so a construct cannot hide
# behind a comment, a string literal, or a helper variable — and `//` inside a
# dependency URL cannot be mistaken for a comment, which is exactly what a
# source-text scanner gets wrong here.
#
# Bash 3.2 compatible (macOS ships 3.2).

set -euo pipefail
cd "$(dirname "$0")/.."

# Each check is a name, a pattern matched against the manifest JSON, and the
# explanation a reader needs at the moment it fires.
#
# The patterns match JSON *keys*, which dump-package emits verbatim, so a
# dependency URL that happens to contain the word "branch" cannot trip them.
check_manifest() {
    local json="$1" failures=0 flat targets settings unsafe gated
    # dump-package sorts its keys, so once the whitespace is gone a setting
    # reads {"condition":{…,"traits":[…]},"kind":{"unsafeFlags":{"_0":[…]}},
    # "tool":"…"}. Here-strings rather than `printf | grep -q`: under
    # pipefail, a grep that stops at its first match leaves printf writing a
    # large manifest into a closed pipe, and the pipeline's SIGPIPE status
    # then reads as "no match".
    flat=$(tr -d ' \t\r\n' <<<"$json")

    # The manifest's target names, |-separated: the "name" keys from the
    # top-level "targets":[{ on (a product's "targets" holds bare strings,
    # and nothing inside a target has a "name" key).
    targets=$(awk '{
        i = index($0, "\"targets\":[{")
        if (!i) exit
        rest = substr($0, i)
        while (match(rest, /"name":"[^"]*"/)) {
            print substr(rest, RSTART + 8, RLENGTH - 9)
            rest = substr(rest, RSTART + RLENGTH)
        }
    }' <<<"$flat" | tr '\n' '|')

    # Each unsafeFlags setting, one per line: its tool (the first "tool" key
    # after the setting's kind), a space, and for a linker setting `ok` if
    # its flags are TUIkit's unexport patterns and nothing else, `bad` if not.
    # Whatever shape the flags' value takes (`{"_0":[…]}` today, `[[…]]` in
    # older SwiftPMs), a `"tool":"` cannot occur inside it, because JSON
    # escapes the quotes in a flag; the flags are the strings from the first
    # `["` to the next `"]` before it. A flag holding an escaped `"]` would
    # end them early and read `bad`, the safe direction. A pattern is
    # `_$s` + the module name's length + the name + `*`, the start of every
    # symbol Swift mangles for that module, for a target of this manifest
    # named TUIkit…, so that it can never match another package's symbols.
    # `?` is a setting with no tool after it: JSON in a shape this does not
    # read. The flags are cut out with index() rather than with a regex for
    # a literal `[` or `]`, which mawk (the Lint job's awk) and macOS's awk
    # need not read alike.
    settings=$(awk -v targets="|$targets" '
        function unexport_list(flags,    f, n, k, p, digits, name) {
            n = split(flags, f, /","/)
            if (n == 0 || n % 4 != 0) return 0
            for (k = 1; k <= n; k += 4) {
                if (f[k] != "-Xlinker" || f[k + 1] != "-unexported_symbol" || f[k + 2] != "-Xlinker") return 0
                p = f[k + 3]
                if (!match(p, /^_\$s[0-9]+TUIkit[A-Za-z0-9_]*\*$/)) return 0
                match(p, /^_\$s[0-9]+/)
                digits = substr(p, 4, RLENGTH - 3)
                name = substr(p, RLENGTH + 1, length(p) - RLENGTH - 1)
                if (length(name) != digits + 0 || index(targets, "|" name "|") == 0) return 0
            }
            return 1
        }
        {
            n = split($0, part, /"kind":[{]"unsafeFlags":/)
            for (i = 2; i <= n; i++) {
                if (!match(part[i], /"tool":"[^"]*"/)) { print "?"; continue }
                tool = substr(part[i], RSTART + 8, RLENGTH - 9)
                region = substr(part[i], 1, RSTART - 1)
                flags = ""
                a = index(region, "[\"")
                if (a) {
                    rest = substr(region, a + 2)
                    b = index(rest, "\"]")
                    if (b) flags = substr(rest, 1, b - 1)
                }
                print tool " " (tool == "linker" ? (unexport_list(flags) ? "ok" : "bad") : "-")
            }
        }' <<<"$flat")

    if grep -qx 'linker bad' <<<"$settings"; then
        printf 'FAIL unsafeFlags in a linker setting, other than -unexported_symbol for a TUIkit module\n'
        printf '     A package'"'"'s linker flags land on the app'"'"'s final link and change\n'
        printf '     the developer'"'"'s whole program. Offer the flag in the README instead.\n'
        printf '     The one allowed is -Xlinker -unexported_symbol -Xlinker '"'"'_$s<length><module>*'"'"'\n'
        printf '     for a target of this package named TUIkit…, which touches only what Swift names under it.\n'
        failures=$((failures + 1))
    fi
    if grep -qx '?' <<<"$settings"; then
        printf 'FAIL an unsafeFlags setting names no tool\n'
        printf '     dump-package'"'"'s JSON is not in the shape this script reads, so it\n'
        printf '     cannot tell a linker flag from a compile one: update check_manifest.\n'
        failures=$((failures + 1))
    fi

    unsafe=$(grep -oE '"kind":\{"unsafeFlags"' <<<"$flat" | wc -l | tr -d ' ')
    gated=$(grep -oE '"traits":\[[^]]+\]\},"kind":\{"unsafeFlags"' <<<"$flat" | wc -l | tr -d ' ')
    if [ "$unsafe" != "$gated" ]; then
        printf 'FAIL unsafeFlags without a trait\n'
        printf '     %s of %s unsafeFlags settings name no trait in their condition. A\n' \
            "$((unsafe - gated))" "$unsafe"
        printf '     client can undo such a flag only by turning off the trait that\n'
        printf '     adds it: gate it with .when(…, traits: [...]).\n'
        failures=$((failures + 1))
    fi

    if grep -q '"fileSystem"' <<<"$flat"; then
        printf 'FAIL local path dependency\n'
        printf '     A .package(path:) dependency exists only on this machine. A consumer\n'
        printf '     resolving this package by version cannot follow it.\n'
        failures=$((failures + 1))
    fi

    if grep -qE '"requirement":\{"(branch|revision)"' <<<"$flat"; then
        printf 'FAIL branch or revision dependency\n'
        printf '     A versioned package may only depend on other packages by version.\n'
        printf '     A branch or revision pin makes this package unresolvable downstream.\n'
        failures=$((failures + 1))
    fi

    return $failures
}

# The checks are only worth having if they actually fire, so prove it against
# synthetic manifests rather than trusting the patterns by eye. Each fixture is
# the shape `swift package dump-package` emits for that construct.
self_test() {
    local failures=0 name json

    # `want` is "pass", or the checks that must fire, by their FAIL titles,
    # joined with ";": a case caught by some other check proves nothing.
    run_case() {
        name="$1"; json="$2"; local want="$3" out got status=0
        out=$(check_manifest "$json" 2>&1) || status=$?
        got=$(sed -n 's/^FAIL //p' <<<"$out" | paste -sd ';' -)
        [ -n "$got" ] || got=pass
        if [ "$got" != "$want" ] || { [ "$got" = pass ] && [ "$status" -ne 0 ]; } \
            || { [ "$got" != pass ] && [ "$status" -eq 0 ]; }; then
            printf 'SELF-TEST FAIL: %s (expected %s, got %s, exit %s)\n' "$name" "$want" "$got" "$status"
            failures=$((failures + 1))
        else
            printf 'ok  %s\n' "$name"
        fi
    }

    local linker='unsafeFlags in a linker setting, other than -unexported_symbol for a TUIkit module'
    local untraited='unsafeFlags without a trait'
    local swift_gated='{"condition":{"config":"release","platformNames":["macos"],"traits":["T"]},"kind":{"unsafeFlags":{"_0":["-Xfrontend","-internalize-at-link"]}},"tool":"swift"}'
    local linker_gated='{"condition":{"traits":["T"]},"kind":{"unsafeFlags":{"_0":["-Xlinker","-deduplicate"]}},"tool":"linker"}'
    # A linker setting with these flags, behind a trait, on a target named TUIkitCore.
    unexport() {
        printf '{"targets":[{"name":"TUIkitCore","settings":[{"condition":{"config":"release","traits":["T"]},"kind":{"unsafeFlags":{"_0":[%s]}},"tool":"linker"}]}]}' "$1"
    }

    run_case "clean manifest passes" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","requirement":{"range":[{"lowerBound":"1.0.0","upperBound":"2.0.0"}]}}]}],"targets":[{"name":"T","settings":[]}]}' pass
    run_case "a compile flag behind a trait passes" \
        "{\"targets\":[{\"name\":\"T\",\"settings\":[$swift_gated]}]}" pass
    run_case "a compile flag without a trait caught" \
        '{"targets":[{"name":"T","settings":[{"condition":{"config":"release"},"kind":{"unsafeFlags":{"_0":["-Xfrontend","-internalize-at-link"]}},"tool":"swift"}]}]}' "$untraited"
    run_case "a compile flag with no condition caught" \
        '{"targets":[{"name":"T","settings":[{"kind":{"unsafeFlags":{"_0":["-Onone"]}},"tool":"swift"}]}]}' "$untraited"
    run_case "a linker flag caught, even behind a trait" \
        "{\"targets\":[{\"name\":\"T\",\"settings\":[$linker_gated]}]}" "$linker"
    run_case "a linker flag without a trait caught by both checks" \
        '{"targets":[{"name":"T","settings":[{"kind":{"unsafeFlags":{"_0":["-Xlinker","-x"]}},"tool":"linker"}]}]}' "$linker;$untraited"
    # The same shape as dump-package prints it, over many lines.
    run_case "a pretty-printed linker flag behind a trait caught" \
        "$(printf '{\n  "targets" : [\n    {\n      "settings" : [\n        {\n          "condition" : {\n            "traits" : [\n              "T"\n            ]\n          },\n          "kind" : {\n            "unsafeFlags" : {\n              "_0" : [\n                "-Xlinker",\n                "-x"\n              ]\n            }\n          },\n          "tool" : "linker"\n        }\n      ]\n    }\n  ]\n}')" "$linker"
    # Older SwiftPMs encoded the flags as an array of arrays; the linker check
    # must not depend on how the value is spelled.
    run_case "a linker flag in the older encoding caught" \
        '{"targets":[{"name":"T","settings":[{"condition":{"traits":["T"]},"kind":{"unsafeFlags":[["-Xlinker","-deduplicate"]]},"tool":"linker"}]}]}' "$linker"

    # TUIkit's own unexport patterns: the one linker flag allowed, and only
    # in exactly that form.
    run_case "a TUIkit module's unexport pattern behind a trait passes" \
        "$(unexport '"-Xlinker","-unexported_symbol","-Xlinker","_$s10TUIkitCore*"')" pass
    run_case "a pretty-printed unexport pattern passes" \
        "$(printf '{\n  "targets" : [\n    {\n      "name" : "TUIkitCore",\n      "settings" : [\n        {\n          "condition" : {\n            "traits" : [\n              "T"\n            ]\n          },\n          "kind" : {\n            "unsafeFlags" : {\n              "_0" : [\n                "-Xlinker",\n                "-unexported_symbol",\n                "-Xlinker",\n                "_$s10TUIkitCore*"\n              ]\n            }\n          },\n          "tool" : "linker"\n        }\n      ]\n    }\n  ]\n}')" pass
    run_case "an unexport pattern in the older encoding passes" \
        '{"targets":[{"name":"TUIkitCore","settings":[{"condition":{"traits":["T"]},"kind":{"unsafeFlags":[["-Xlinker","-unexported_symbol","-Xlinker","_$s10TUIkitCore*"]]},"tool":"linker"}]}]}' pass
    run_case "an unexport pattern without a trait caught" \
        '{"targets":[{"name":"TUIkitCore","settings":[{"condition":{"config":"release"},"kind":{"unsafeFlags":{"_0":["-Xlinker","-unexported_symbol","-Xlinker","_$s10TUIkitCore*"]}},"tool":"linker"}]}]}' "$untraited"
    run_case "another package's module caught" \
        "$(unexport '"-Xlinker","-unexported_symbol","-Xlinker","_$s3Lib*"')" "$linker"
    run_case "a length that is not the name's caught" \
        "$(unexport '"-Xlinker","-unexported_symbol","-Xlinker","_$s9TUIkitCore*"')" "$linker"
    run_case "a TUIkit… name that is no target here caught" \
        "$(unexport '"-Xlinker","-unexported_symbol","-Xlinker","_$s9TUIkitFoo*"')" "$linker"
    run_case "a wider wildcard caught" \
        "$(unexport '"-Xlinker","-unexported_symbol","-Xlinker","_$s*"')" "$linker"
    run_case "a prefix without its wildcard caught" \
        "$(unexport '"-Xlinker","-unexported_symbol","-Xlinker","_$s10TUIkitCore"')" "$linker"
    run_case "an unexport list file caught" \
        "$(unexport '"-Xlinker","-unexported_symbols_list","-Xlinker","/tmp/list"')" "$linker"
    run_case "another flag beside the pattern caught" \
        "$(unexport '"-Xlinker","-unexported_symbol","-Xlinker","_$s10TUIkitCore*","-Xlinker","-deduplicate"')" "$linker"
    # Each setting's own tool, wherever it sits among the others.
    run_case "a linker flag after a compile one caught" \
        "{\"targets\":[{\"name\":\"T\",\"settings\":[$swift_gated,$linker_gated]}]}" "$linker"
    run_case "a compile flag after a linker one does not hide it" \
        "{\"targets\":[{\"name\":\"T\",\"settings\":[$linker_gated,$swift_gated]}]}" "$linker"
    run_case "a setting with no tool cannot be read" \
        '{"targets":[{"name":"T","settings":[{"condition":{"traits":["T"]},"kind":{"unsafeFlags":{"_0":["-x"]}}}]}]}' 'an unsafeFlags setting names no tool'
    run_case "path dependency caught" \
        '{"dependencies":[{"fileSystem":[{"identity":"local","path":"/Users/someone/dep"}]}]}' 'local path dependency'
    run_case "branch dependency caught" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","requirement":{"branch":["main"]}}]}]}' 'branch or revision dependency'
    run_case "revision dependency caught" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","requirement":{"revision":["abc123"]}}]}]}' 'branch or revision dependency'
    # A URL containing a check word must NOT trip the scanner — the reason this
    # reads dump-package's JSON keys rather than the manifest source.
    run_case "a URL containing 'branch' is not a branch pin" \
        '{"dependencies":[{"sourceControl":[{"identity":"x","location":{"remote":[{"urlString":"https://example.com/branch/revision"}]},"requirement":{"exact":["1.0.0"]}}]}]}' pass

    if [ "$failures" -eq 0 ]; then
        printf '\nself-test passed: every check fires on its construct and on nothing else\n'
        return 0
    fi
    printf '\n%d self-test failure(s)\n' "$failures"
    return 1
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

manifest_json="$(swift package dump-package)"

if check_manifest "$manifest_json"; then
    printf 'Package.swift is consumable: no linker unsafeFlags but the TUIkit unexport patterns, every unsafeFlags behind a trait, no path/branch/revision dependencies\n'
    exit 0
fi

printf '\nSee Tools/validate-package-manifest.sh for why each of these is fatal to a consumer.\n'
exit 1
