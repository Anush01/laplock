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

# Get server URL
if [ -f "$CONFIG_DIR/server_url" ]; then
    EXISTING_URL=$(cat "$CONFIG_DIR/server_url" | tr -d '[:space:]')
    echo "Existing server URL found: $EXISTING_URL"
    read -p "Use existing server URL? [Y/n]: " USE_EXISTING_URL
    if [ "$USE_EXISTING_URL" != "n" ] && [ "$USE_EXISTING_URL" != "N" ]; then
        SERVER_URL="$EXISTING_URL"
    fi
fi

if [ -z "$SERVER_URL" ]; then
    read -p "Enter your server URL (e.g. https://your-app.onrender.com): " SERVER_URL
    if [ -z "$SERVER_URL" ]; then
        echo "ERROR: Server URL is required."
        exit 1
    fi
fi

# Strip trailing slash
SERVER_URL="${SERVER_URL%/}"

echo ""
echo "Using server: $SERVER_URL"
echo ""

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
    read -p "Enter topic (or press Enter for random): " USER_TOPIC
    TOPIC="${USER_TOPIC:-$DEFAULT_TOPIC}"
fi

echo ""
echo "Using topic: $TOPIC"
echo ""

# Get auth token (optional)
if [ -f "$CONFIG_DIR/token" ]; then
    EXISTING_TOKEN=$(cat "$CONFIG_DIR/token" | tr -d '[:space:]')
    echo "Existing auth token found."
    read -p "Use existing token? [Y/n]: " USE_EXISTING_TOKEN
    if [ "$USE_EXISTING_TOKEN" != "n" ] && [ "$USE_EXISTING_TOKEN" != "N" ]; then
        AUTH_TOKEN="$EXISTING_TOKEN"
    fi
fi

if [ -z "$AUTH_TOKEN" ]; then
    read -p "Enter auth token (or press Enter to skip): " AUTH_TOKEN
fi

if [ -n "$AUTH_TOKEN" ]; then
    echo "Token configured."
else
    echo "No token — using unauthenticated access."
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
echo "$SERVER_URL" > "$CONFIG_DIR/server_url"
echo "$TOPIC" > "$CONFIG_DIR/topic"
if [ -n "$AUTH_TOKEN" ]; then
    echo "$AUTH_TOKEN" > "$CONFIG_DIR/token"
    chmod 600 "$CONFIG_DIR/token"
fi

# Generate and install plist
sed \
    -e "s|__BINARY_PATH__|$INSTALL_DIR/$BINARY_NAME|g" \
    -e "s|__SERVER_URL__|$SERVER_URL|g" \
    -e "s|__TOPIC__|$TOPIC|g" \
    -e "s|__AUTH_TOKEN__|${AUTH_TOKEN}|g" \
    -e "s|__HOME__|$HOME|g" \
    "$SCRIPT_DIR/com.macbook-notify.agent.plist" > "$PLIST_DEST"

echo "Installed LaunchAgent to $PLIST_DEST"

# Load agent
launchctl load "$PLIST_DEST"
echo "Agent loaded and running."

echo ""
echo "=== Setup complete ==="
echo ""
echo "  Server: $SERVER_URL"
echo "  Topic:  $TOPIC"
echo "  Status: open index.html on your phone and enter the server URL + topic"
echo ""
echo "  Logs:   tail -f $LOG_DIR/stderr.log"
echo "  Remove: ./uninstall.sh"
echo ""
