#!/bin/bash
# Installer script for macOS and Linux (Bash)
# Copies statusline.sh to ~/.gemini/ and updates settings.json statusLine command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_DIR="$HOME/.gemini"
DEST_SCRIPT="$GEMINI_DIR/statusline.sh"
CONFIG_FILE="$GEMINI_DIR/statusline.json"
BACKUP_FILE="$GEMINI_DIR/statusline.prev.json"
SETTINGS_FILE="$GEMINI_DIR/antigravity-cli/settings.json"

echo "Installing Unified AGY Statusline..."

if ! command -v jq &>/dev/null; then
    echo "Error: 'jq' is not installed. It is required to install and run the Unified AGY Statusline."
    echo "Please install jq using your package manager (e.g., 'brew install jq' on macOS or 'sudo apt install jq' on Debian/Ubuntu) and try again."
    exit 1
fi

mkdir -p "$GEMINI_DIR"
echo "Ensured directory exists: $GEMINI_DIR"

if [ ! -f "$SCRIPT_DIR/statusline.sh" ]; then
    echo "Error: statusline.sh not found in $SCRIPT_DIR"
    exit 1
fi
cp "$SCRIPT_DIR/statusline.sh" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"
echo "Copied statusline.sh to: $DEST_SCRIPT"

if [ ! -f "$CONFIG_FILE" ]; then
    cat <<EOF >"$CONFIG_FILE"
{
  "show_quota": true,
  "show_additional_stats": true,
  "hide_zero_stats": true,
  "show_state_indicator": true
}
EOF
    echo "Created default configuration at: $CONFIG_FILE"
else
    echo "Configuration file already exists at $CONFIG_FILE (skipping override)."
fi

read -r -d '' MANUAL_SNIPPET <<EOF || true
  "statusLine": {
    "type": "command",
    "command": "$DEST_SCRIPT",
    "enabled": true
  }
EOF

if [ -f "$SETTINGS_FILE" ]; then
    temp_settings=$(mktemp)
    trap 'rm -f "$temp_settings"' EXIT

    has_statusline=$(jq -r 'has("statusLine")' "$SETTINGS_FILE" 2>/dev/null || echo "false")
    if [ "$has_statusline" = "false" ]; then
        if [ ! -f "$BACKUP_FILE" ]; then
            printf '{"__absent__":true}\n' >"$BACKUP_FILE"
        fi
    else
        prev_cmd=$(jq -r '.statusLine.command // ""' "$SETTINGS_FILE" 2>/dev/null || echo "")
        case "$prev_cmd" in
            *statusline.sh*) ;;
            *)
                jq '.statusLine' "$SETTINGS_FILE" >"$BACKUP_FILE" 2>/dev/null || true
                echo "Backed up previous statusLine config to: $BACKUP_FILE"
                ;;
        esac
    fi

    if jq --arg cmd "$DEST_SCRIPT" '.statusLine = {type: "command", command: $cmd, enabled: true}' "$SETTINGS_FILE" >"$temp_settings"; then
        mv "$temp_settings" "$SETTINGS_FILE"
        echo "Successfully updated settings.json statusLine configuration!"
    else
        echo "Warning: Failed to update $SETTINGS_FILE with jq."
        echo "Please manually add the following configuration to $SETTINGS_FILE:"
        echo "$MANUAL_SNIPPET"
    fi
else
    echo "Warning: settings.json not found at $SETTINGS_FILE. Please configure agy statusline manually."
    echo "Please manually add the following configuration to $SETTINGS_FILE:"
    echo "$MANUAL_SNIPPET"
fi
