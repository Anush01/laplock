#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY_NAME="macbook-notify"
INSTALL_DIR="$HOME/.local/bin"
PLIST_LABEL="com.macbook-notify.agent"
PLIST_DEST="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/macbook-notify"
CONFIG_DIR="$HOME/.config/macbook-notify"

echo "=== macbook-notify installer ==="
echo ""

# Check for swiftc
if ! command -v swiftc &>/dev/null; then
    echo "ERROR: swiftc not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# Unload existing agent if present
if launchctl list | grep -q "$PLIST_LABEL" 2>/dev/null; then
    echo "Stopping existing agent..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Get or generate topic
if [ -f "$CONFIG_DIR/topic" ]; then
    EXISTING_TOPIC=$(cat "$CONFIG_DIR/topic" | tr -d '[:space:]')
    echo "Existing topic found: $EXISTING_TOPIC"
    read -p "Use existing topic? [Y/n]: " USE_EXISTING
    if [ "$USE_EXISTING" != "n" ] && [ "$USE_EXISTING" != "N" ]; then
        TOPIC="$EXISTING_TOPIC"
    fi
fi

if [ -z "$TOPIC" ]; then
    DEFAULT_TOPIC=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-')
    read -p "Enter ntfy topic (or press Enter for random): " USER_TOPIC
    TOPIC="${USER_TOPIC:-$DEFAULT_TOPIC}"
fi

echo ""
echo "Using topic: $TOPIC"
echo ""

# Get ntfy token (optional, for authenticated access)
if [ -f "$CONFIG_DIR/token" ]; then
    EXISTING_TOKEN=$(cat "$CONFIG_DIR/token" | tr -d '[:space:]')
    echo "Existing ntfy token found."
    read -p "Use existing token? [Y/n]: " USE_EXISTING_TOKEN
    if [ "$USE_EXISTING_TOKEN" != "n" ] && [ "$USE_EXISTING_TOKEN" != "N" ]; then
        NTFY_TOKEN="$EXISTING_TOKEN"
    fi
fi

if [ -z "$NTFY_TOKEN" ]; then
    read -p "Enter ntfy access token (or press Enter to skip): " NTFY_TOKEN
fi

if [ -n "$NTFY_TOKEN" ]; then
    echo "Token configured."
else
    echo "No token — using anonymous access (free-tier rate limits apply)."
fi
echo ""

# Compile
echo "Compiling..."
swiftc -O "$SCRIPT_DIR/Sources/MacBookNotify.swift" -o "$SCRIPT_DIR/$BINARY_NAME"
echo "Compiled successfully."

# Install binary
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"
echo "Installed binary to $INSTALL_DIR/$BINARY_NAME"

# Create log directory
mkdir -p "$LOG_DIR"

# Save config
mkdir -p "$CONFIG_DIR"
echo "$TOPIC" > "$CONFIG_DIR/topic"
if [ -n "$NTFY_TOKEN" ]; then
    echo "$NTFY_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
fi

# Generate and install plist
sed \
    -e "s|__BINARY_PATH__|$INSTALL_DIR/$BINARY_NAME|g" \
    -e "s|__NTFY_TOPIC__|$TOPIC|g" \
    -e "s|__NTFY_TOKEN__|${NTFY_TOKEN}|g" \
    -e "s|__HOME__|$HOME|g" \
    "$SCRIPT_DIR/com.macbook-notify.agent.plist" > "$PLIST_DEST"

echo "Installed LaunchAgent to $PLIST_DEST"

# Load agent
launchctl load "$PLIST_DEST"
echo "Agent loaded and running."

echo ""
echo "=== Setup complete ==="
echo ""
echo "  Topic:  $TOPIC"
echo "  Status: open web/index.html on your phone and enter the topic above"
echo ""
echo "  Logs:   tail -f $LOG_DIR/stderr.log"
echo "  Remove: ./uninstall.sh"
echo ""
