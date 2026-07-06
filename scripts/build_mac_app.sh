#!/usr/bin/env bash

# Builds "ACP.app" (Apple Calendar Protocol) — the windowed SwiftUI app.
# It is the same executable as the MCP server / CLI, bundled so macOS treats it
# as a regular GUI app (Dock icon, window, and a stable identity for the
# Calendar permission grant). LSEnvironment forces GUI mode on launch.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
configuration="${1:-release}"
case "${configuration}" in
  debug|release)
    ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

echo "🔨 Building AppleCalendarMCPServer (${configuration})..."
( cd "${project_root}" && swift build -c "${configuration}" )

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

app_name="ACP"
bundle_root="$(dirname "${binary_path}")/${app_name}.app"
contents_dir="${bundle_root}/Contents"
macos_dir="${contents_dir}/MacOS"
plist_path="${contents_dir}/Info.plist"
bundled_binary="${macos_dir}/ACP"

rm -rf "${bundle_root}"
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
  <string>ACP</string>
  <key>CFBundleExecutable</key>
  <string>ACP</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.openai.codex.acp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ACP</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSEnvironment</key>
  <dict>
    <key>APPLE_CALENDAR_APP_MODE</key>
    <string>1</string>
  </dict>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>ACP (Apple Calendar Protocol) reads and manages your events, and configures the local MCP server.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>ACP (Apple Calendar Protocol) reads and manages your events, and configures the local MCP server.</string>
</dict>
</plist>
PLIST

# Bundle the app icon when it has been generated (scripts/make_app_icon.sh).
if [[ -f "${project_root}/Resources/AppIcon.icns" ]]; then
  mkdir -p "${contents_dir}/Resources"
  cp "${project_root}/Resources/AppIcon.icns" "${contents_dir}/Resources/AppIcon.icns"
fi

# Choose a signing identity. A stable (Developer) identity lets macOS persist the
# Calendar (TCC) permission grant across rebuilds. Ad-hoc signatures are keyed to
# the binary's cdhash, so the grant is lost every time the app is rebuilt.
# Override with: ACP_CODESIGN_IDENTITY="Apple Development: ..." ./scripts/build_mac_app.sh
codesign_identity="${ACP_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
if [[ -z "${codesign_identity}" ]]; then
  codesign_identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Developer ID Application|Apple Development/ {print $2; exit}')"
fi

if [[ -z "${codesign_identity}" ]]; then
  codesign_identity="-"
  echo "⚠️  No Developer signing identity found — using ad-hoc signing." >&2
  echo "   macOS ties ad-hoc Calendar permission to the binary hash, so you will" >&2
  echo "   have to re-grant Calendar access after every rebuild." >&2
else
  echo "🔏 Signing with stable identity: ${codesign_identity}"
fi

codesign --force --sign "${codesign_identity}" "${bundled_binary}"
codesign --force --sign "${codesign_identity}" "${bundle_root}"

echo "✅ Built ${bundle_root}"
echo ""
echo "Launch it with:"
echo "  open \"${bundle_root}\""
printf '%s\n' "${bundle_root}"
