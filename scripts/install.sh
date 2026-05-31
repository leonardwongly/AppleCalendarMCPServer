#!/bin/bash
set -e

echo "🔨 Building ical CLI..."
cd "$(dirname "$0")/.."

# Build release binary
swift build -c release

# Determine output path
BINARY_PATH="./.build/release/AppleCalendarMCPServer"
INSTALL_PATH="/usr/local/bin/ical"

if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Build failed - binary not found"
    exit 1
fi

echo "📦 Installing to $INSTALL_PATH..."

# Create /usr/local/bin if needed
sudo mkdir -p /usr/local/bin

# Copy binary
sudo cp "$BINARY_PATH" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

# Verify installation
if command -v ical &> /dev/null; then
    echo "✅ Installation successful!"
    echo ""
    echo "Usage:"
    echo "  ical list calendars"
    echo "  ical search events --calendar ID [--from DATE] [--to DATE] [--query TEXT]"
    echo "  ical create event --calendar ID --title TEXT --start DATETIME --end DATETIME [--location TEXT] [--url URL]"
    echo "  ical update event EVENT_ID [--title TEXT] [--start DATETIME] [--end DATETIME] [--location TEXT] [--url URL]"
    echo "  ical delete event EVENT_ID"
    echo ""
    echo "Add --json flag to any command for JSON output"
    echo ""
    ical list calendars | head -3
else
    echo "❌ Installation verification failed"
    exit 1
fi
