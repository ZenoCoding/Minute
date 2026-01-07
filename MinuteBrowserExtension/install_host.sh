#!/bin/bash

# Configuration
HOST_NAME="com.tychoyoung.minute.browser"
MANIFEST_NAME="${HOST_NAME}.json"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_SOURCE="${PROJECT_DIR}/${MANIFEST_NAME}"
HOST_SCRIPT="${PROJECT_DIR}/native-host/minute-browser-host"

# Ensure host is executable
chmod +x "$HOST_SCRIPT"

# Target directories for common browsers
TARGET_DIRS=(
    "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    "$HOME/Library/Application Support/Arc/User Data/NativeMessagingHosts"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
    "$HOME/Library/Application Support/Vivaldi/NativeMessagingHosts"
    "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
    # Specific for 'Dia' if it follows standard Chromium structure?
    "$HOME/Library/Application Support/Dia/NativeMessagingHosts" 
)

echo "Installing Minute Browser Host..."
echo "Host Script: $HOST_SCRIPT"
echo "Manifest: $MANIFEST_SOURCE"

for DIR in "${TARGET_DIRS[@]}"; do
    if [ -d "$(dirname "$DIR")" ]; then
        echo "Found browser directory: $(dirname "$DIR")"
        mkdir -p "$DIR"
        cp "$MANIFEST_SOURCE" "$DIR/"
        echo "✅ Installed to $DIR"
    fi
done

echo "Done! Please restart your browser."
