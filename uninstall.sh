#!/bin/bash
set -e

PLIST_LABEL="com.macbook-notify.agent"
PLIST_DEST="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
BINARY="$HOME/.local/bin/macbook-notify"
LOG_DIR="$HOME/Library/Logs/macbook-notify"
CONFIG_DIR="$HOME/.config/macbook-notify"

echo "=== macbook-notify uninstaller ==="
echo ""

# Unload agent
if launchctl list | grep -q "$PLIST_LABEL" 2>/dev/null; then
    echo "Stopping agent..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Remove files
[ -f "$PLIST_DEST" ] && rm "$PLIST_DEST" && echo "Removed $PLIST_DEST"
[ -f "$BINARY" ] && rm "$BINARY" && echo "Removed $BINARY"
[ -d "$LOG_DIR" ] && rm -rf "$LOG_DIR" && echo "Removed $LOG_DIR"
[ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR" && echo "Removed $CONFIG_DIR"

echo ""
echo "macbook-notify has been uninstalled."
