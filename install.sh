#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="/usr/local/bin/lfm"

sudo install -m 0755 "$SCRIPT_DIR/lfm.sh" "$TARGET"

echo "Installed lfm to $TARGET"
