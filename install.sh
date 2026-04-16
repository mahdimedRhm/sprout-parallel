#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SRC="$SCRIPT_DIR/sprout-parallel"

# Make the script executable
chmod +x "$SCRIPT_SRC"

# Determine install directory
if [[ -d "$HOME/.local/bin" ]]; then
  INSTALL_DIR="$HOME/.local/bin"
elif [[ -w "/usr/local/bin" ]]; then
  INSTALL_DIR="/usr/local/bin"
else
  echo "Error: Neither ~/.local/bin nor /usr/local/bin is available." >&2
  echo "Create ~/.local/bin and add it to your PATH, then re-run this script." >&2
  exit 1
fi

INSTALL_TARGET="$INSTALL_DIR/sprout-parallel"

ln -sf "$SCRIPT_SRC" "$INSTALL_TARGET"
echo "Installed: $INSTALL_TARGET -> $SCRIPT_SRC"
echo ""
echo "If '$INSTALL_DIR' is not on your PATH, add this to your ~/.zshrc or ~/.bashrc:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "Verify installation:"
echo "  sprout-parallel --help"
