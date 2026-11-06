#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/ai-check
swiftc -O -swift-version 5 -module-cache-path "$PWD/.build/ai-check/module-cache" Sources/Qingyi/AITranslation.swift Tests/AITranslationTests.swift -o .build/ai-check/check
.build/ai-check/check
