#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/shortcut-check
swiftc -O -swift-version 5 -module-cache-path "$PWD/.build/shortcut-check/module-cache" Sources/Qingyi/Hotkeys.swift Tests/ShortcutRegression/Check.swift -o .build/shortcut-check/check
.build/shortcut-check/check
