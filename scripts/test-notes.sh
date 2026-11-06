#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/notes-check
swiftc -O -swift-version 5 -module-cache-path "$PWD/.build/notes-check/module-cache" Sources/Qingyi/NotesArchive.swift Tests/NotesRegression/Check.swift -o .build/notes-check/check
.build/notes-check/check
osacompile -o .build/notes-check/NotesArchive.scpt Resources/NotesArchive.applescript
osascript Tests/NotesRegression/CheckFormatting.applescript "$PWD/.build/notes-check/NotesArchive.scpt"
