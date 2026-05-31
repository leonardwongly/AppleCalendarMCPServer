#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
configuration="${1:-debug}"
case "${configuration}" in
  debug|release)
    ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

candidates=(
  "${project_root}/.build/arm64-apple-macosx/${configuration}/AppleCalendarMCPServer"
  "${project_root}/.build/aarch64-apple-macosx/${configuration}/AppleCalendarMCPServer"
  "${project_root}/.build/${configuration}/AppleCalendarMCPServer"
  "${project_root}/.build/x86_64-apple-macosx/${configuration}/AppleCalendarMCPServer"
)

binary_path=""
for candidate in "${candidates[@]}"; do
  if [[ -x "${candidate}" ]]; then
    binary_path="${candidate}"
    break
  fi
done

if [[ -z "${binary_path}" ]]; then
  echo "Built AppleCalendarMCPServer binary not found. Run 'swift build' first." >&2
  exit 2
fi

bundle_root="$(dirname "${binary_path}")/AppleCalendarMCPServer.app"
contents_dir="${bundle_root}/Contents"
macos_dir="${contents_dir}/MacOS"
plist_path="${contents_dir}/Info.plist"
bundled_binary="${macos_dir}/AppleCalendarMCPServer"

mkdir -p "${macos_dir}"
cp "${binary_path}" "${bundled_binary}"
chmod 755 "${bundled_binary}"

cat > "${plist_path}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Apple Calendar MCP Server</string>
  <key>CFBundleExecutable</key>
  <string>AppleCalendarMCPServer</string>
  <key>CFBundleIdentifier</key>
  <string>com.openai.codex.apple-calendar-mcp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AppleCalendarMCPServer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Codex uses Apple Calendar access to read and manage your events through the local MCP server.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>Codex uses Apple Calendar access to read and manage your events through the local MCP server.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "${bundled_binary}"
codesign --force --sign - "${bundle_root}"

printf '%s\n' "${bundled_binary}"
