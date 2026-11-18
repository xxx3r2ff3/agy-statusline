#!/bin/bash
# Uninstaller script for macOS and Linux (Bash)
# Restores previous statusLine configuration (if backed up) and removes installed script.
set -euo pipefail

GEMINI_DIR="$HOME/.gemini"
DEST_SCRIPT="$GEMINI_DIR/statusline.sh"
CONFIG_FILE="$GEMINI_DIR/statusline.json"
BACKUP_FILE="$GEMINI_DIR/statusline.prev.json"
SETTINGS_FILE="$GEMINI_DIR/antigravity-cli/settings.json"

echo "Uninstalling Unified AGY Statusline..."

if [ -f "$SETTINGS_FILE" ]; then
    if command -v jq &>/dev/null; then
        temp_settings=$(mktemp)
        trap 'rm -f "$temp_settings"' EXIT

        if [ -f "$BACKUP_FILE" ]; then
            is_absent=$(jq -r '.__absent__ // false' "$BACKUP_FILE" 2>/dev/null || echo "false")
            if [ "$is_absent" = "true" ]; then
                jq 'del(.statusLine)' "$SETTINGS_FILE" >"$temp_settings"
                echo "Removed statusLine configuration (none existed prior to install)."
            else
                jq --slurpfile prev "$BACKUP_FILE" '.statusLine = $prev[0]' "$SETTINGS_FILE" >"$temp_settings"
                echo "Restored previous statusLine configuration from backup."
            fi
            mv "$temp_settings" "$SETTINGS_FILE"
            rm -f "$BACKUP_FILE"
        else
            jq '.statusLine = {type: "", command: "", enabled: false}' "$SETTINGS_FILE" >"$temp_settings"
            mv "$temp_settings" "$SETTINGS_FILE"
            echo "Disabled settings.json statusLine configuration."
        fi
    else
        echo "Warning: jq is not installed. Could not update settings.json automatically."
    fi
fi

if [ -f "$DEST_SCRIPT" ]; then
    rm "$DEST_SCRIPT"
    echo "Removed script file: $DEST_SCRIPT"
fi

if [ -f "$CONFIG_FILE" ]; then
    echo "Note: Configuration file left at $CONFIG_FILE to preserve your settings."
fi

echo "Uninstall complete!"
