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
  <string>com.leonardwongly.apple-calendar-mcp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AppleCalendarMCPServer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.1.0</string>
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

# Prefer a stable signing identity so macOS persists the Calendar (TCC) grant
# across rebuilds. Ad-hoc signatures are keyed to the binary hash and lose the
# grant on every rebuild. Override with CODESIGN_IDENTITY="Apple Development: ...".
codesign_identity="${CODESIGN_IDENTITY:-}"
if [[ -z "${codesign_identity}" ]]; then
  codesign_identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Developer ID Application|Apple Development/ {print $2; exit}')"
fi

if [[ -z "${codesign_identity}" ]]; then
  codesign_identity="-"
  echo "⚠️  No Developer signing identity found — using ad-hoc signing." >&2
  echo "   Calendar access will need re-granting after every rebuild." >&2
else
  echo "🔏 Signing with stable identity: ${codesign_identity}" >&2
fi

codesign --force --sign "${codesign_identity}" "${bundled_binary}"
codesign --force --sign "${codesign_identity}" "${bundle_root}"

printf '%s\n' "${bundled_binary}"
