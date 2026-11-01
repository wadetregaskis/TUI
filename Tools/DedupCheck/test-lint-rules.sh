#!/usr/bin/env bash
#
# test-lint-rules.sh — the SwiftLint rules that guard `-Xlinker -deduplicate`,
# key_path_identity and function_address_identity (.swiftlint.yml), and the one
# that guards the concurrency checks, concurrency_escape, flag exactly the lines
# marked in lint-cases/.
#
# A case line ending in `hit: <rule>` must be flagged by that rule, and every
# other line by neither. The rules read only TUI's library sources (their
# `included` is a regex on the path), so the cases are linted from a copy
# under `Sources/TUILintCases/`, with the repository's own configuration.
# A second copy of Positive.swift under each module no app links, the macro
# plugin and the width corpus, must not be flagged at all. Other rules'
# findings on the cases are ignored.
#
#   Tools/DedupCheck/test-lint-rules.sh      # swiftlint on PATH; CI's lint job
#
# Exit status: 0 if every case behaves, 1 if not, 2 if it cannot run.
# Bash 3.2 compatible (macOS ships 3.2).

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
rules='key_path_identity|function_address_identity|concurrency_escape'

command -v swiftlint >/dev/null || { echo "test-lint-rules: no swiftlint on PATH" >&2; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cases="$tmp/Sources/TUILintCases"
mkdir -p "$cases"
cp "$here"/lint-cases/*.swift "$cases/"
hosts=()
for module in TUIMacrosPlugin TUIWidthCorpus; do
    mkdir -p "$tmp/Sources/$module"
    cp "$here/lint-cases/Positive.swift" "$tmp/Sources/$module/"
    hosts+=("$tmp/Sources/$module/Positive.swift")
done

# "Module/File.swift:line rule", one per line, sorted.
expected=$(cd "$tmp/Sources" && grep -nE "hit: ($rules)\$" -- TUILintCases/*.swift \
    | sed -E "s/^([^:]+):([0-9]+):.*hit: ($rules)\$/\1:\2 \3/" | sort)
for rule in key_path_identity function_address_identity concurrency_escape; do
    if ! grep -q " $rule\$" <<<"$expected"; then
        echo "test-lint-rules: no case marks a hit for $rule" >&2
        exit 2
    fi
done
# swiftlint exits non-zero on the error-severity hits it is here to make.
actual=$( (swiftlint lint --no-cache --quiet --config "$repo/.swiftlint.yml" "$cases"/*.swift "${hosts[@]}" \
        2>/dev/null || true) \
    | sed -nE "s#^.*/([^/]+/[^/]+\.swift):([0-9]+):[0-9]+: [a-z]+: .*\(($rules)\)\$#\1:\2 \3#p" | sort -u)

if [ "$expected" = "$actual" ]; then
    printf 'test-lint-rules: %s marked hits, and no other line flagged\n' "$(wc -l <<<"$expected" | tr -d ' ')"
    exit 0
fi
missed=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
extra=$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
[ -z "$missed" ] || printf 'MISSED (marked, not flagged):\n%s\n' "$missed"
[ -z "$extra" ] || printf 'FLAGGED, not marked:\n%s\n' "$extra"
exit 1
