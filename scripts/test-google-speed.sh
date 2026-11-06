#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/google-speed-check
swiftc -O -module-cache-path "$PWD/.build/google-speed-check/module-cache" Sources/TranslationCore/GoogleResultStability.swift Tests/GoogleSpeedRegression/Check.swift -o .build/google-speed-check/check
.build/google-speed-check/check
