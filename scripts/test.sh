#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DEVELOPER_DIR="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
PLUGINS="$DEVELOPER_DIR/usr/lib/swift/host/plugins/testing"

cd "$ROOT"
if [[ -d "$FRAMEWORKS/Testing.framework" && -d "$PLUGINS" ]]; then
    swift test \
        -Xswiftc -F \
        -Xswiftc "$FRAMEWORKS" \
        -Xswiftc -plugin-path \
        -Xswiftc "$PLUGINS"
else
    swift test
fi
