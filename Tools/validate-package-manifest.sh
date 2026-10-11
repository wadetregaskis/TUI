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
#   - Nothing in a LINKER setting. A package's linker flags land on the app's
#     own final link and change the developer's whole program: `-deduplicate`
#     changes which of the app's own key paths compare equal, and a strip flag
#     strips the app's symbols. Those are the developer's to choose; the
#     README offers them, with what each costs.
#   - A COMPILE flag only behind a trait. It reaches every client's build of
#     TUIkit, and no compiler flag undoes another, so the trait is the
#     client's only way to turn it off (`traits: []`). Package.swift's
#     `DeadStripUnusedAPI` is the one there is.
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
    local json="$1" failures=0 flat tools unsafe gated
    # dump-package sorts its keys, so once the whitespace is gone a setting
    # reads {"condition":{…,"traits":[…]},"kind":{"unsafeFlags":{"_0":[…]}},
    # "tool":"…"}. Here-strings rather than `printf | grep -q`: under
    # pipefail, a grep that stops at its first match leaves printf writing a
    # large manifest into a closed pipe, and the pipeline's SIGPIPE status
    # then reads as "no match".
    flat=$(tr -d ' \t\r\n' <<<"$json")

    # Each unsafeFlags setting's tool, one per line: the first "tool" key
    # after the setting's kind. Whatever shape the flags' value takes
    # (`{"_0":[…]}` today, `[[…]]` in older SwiftPMs), a `"tool":"` cannot
    # occur inside it, because JSON escapes the quotes in a flag. `?` is a
    # setting with no tool after it: JSON in a shape this does not read.
    tools=$(awk '{
        n = split($0, part, /"kind":[{]"unsafeFlags":/)
        for (i = 2; i <= n; i++)
            if (match(part[i], /"tool":"[^"]*"/)) print substr(part[i], RSTART + 8, RLENGTH - 9)
            else print "?"
    }' <<<"$flat")

    if grep -qx 'linker' <<<"$tools"; then
        printf 'FAIL unsafeFlags in a linker setting\n'
        printf '     A package'"'"'s linker flags land on the app'"'"'s final link and change\n'
        printf '     the developer'"'"'s whole program. Offer the flag in the README instead.\n'
        failures=$((failures + 1))
    fi
    if grep -qx '?' <<<"$tools"; then
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
        printf '     client can undo a compiler flag only by turning off the trait that\n'
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

    local linker='unsafeFlags in a linker setting' untraited='unsafeFlags without a trait'
    local swift_gated='{"condition":{"config":"release","platformNames":["macos"],"traits":["T"]},"kind":{"unsafeFlags":{"_0":["-Xfrontend","-internalize-at-link"]}},"tool":"swift"}'
    local linker_gated='{"condition":{"traits":["T"]},"kind":{"unsafeFlags":{"_0":["-Xlinker","-deduplicate"]}},"tool":"linker"}'

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
    printf 'Package.swift is consumable: no linker unsafeFlags, every compiler one behind a trait, no path/branch/revision dependencies\n'
    exit 0
fi

printf '\nSee Tools/validate-package-manifest.sh for why each of these is fatal to a consumer.\n'
exit 1
