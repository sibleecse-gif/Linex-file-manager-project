#!/usr/bin/env bash
set -euo pipefail
TARGET="/usr/local/bin/lfm"
if [[ -f "$TARGET" ]]; then
  sudo rm -f "$TARGET"
  echo "Removed $TARGET"
else
  echo "lfm not found at $TARGET"
fi
