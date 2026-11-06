#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
CHECK_DIR="$PWD/.build/provider-check"
mkdir -p "$CHECK_DIR"
swiftc -O -swift-version 5 -module-cache-path "$CHECK_DIR/module-cache" -emit-library -emit-module -module-name TranslationCore Sources/TranslationCore/*.swift -emit-module-path "$CHECK_DIR/TranslationCore.swiftmodule" -o "$CHECK_DIR/libTranslationCore.dylib"
swiftc -O -swift-version 5 -module-cache-path "$CHECK_DIR/module-cache" -I "$CHECK_DIR" -L "$CHECK_DIR" -lTranslationCore Sources/Qingyi/AppModel.swift Sources/Qingyi/Hotkeys.swift Sources/Qingyi/AITranslation.swift Sources/Qingyi/NotesArchive.swift Sources/Qingyi/GooglePageSession.swift Tests/ProviderRegression/Check.swift -o "$CHECK_DIR/check"
DYLD_LIBRARY_PATH="$CHECK_DIR" "$CHECK_DIR/check"
