#!/bin/zsh
# Builds and runs one probe case: ./run.sh <case>
set -e
c=$1
cd "$(dirname $0)"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library -O -D CASE_$c menus.swift -o bin_$c 2>&1 | grep -v warning || true
./bin_$c $c
