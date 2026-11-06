#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
for test in test-ai.sh test-provider-switch.sh test-google-speed.sh test-shortcuts.sh test-notes.sh test-page-session.sh; do
  print "Running $test"
  zsh "scripts/$test"
done
print "PASS all offline regression groups (no paid API calls or personal Notes writes)"
