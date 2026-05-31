#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
tap_name="${HOMEBREW_TAP_NAME:-leonardwongly/apple-calendar}"
tap_user="${tap_name%%/*}"
tap_repo="${tap_name#*/}"
tap_root="$(brew --repository)/Library/Taps/${tap_user}/homebrew-${tap_repo}"
formula_source="${project_root}/Formula/apple-calendar-mcp-server.rb"
formula_target="${tap_root}/Formula/apple-calendar-mcp-server.rb"
branch="$(git -C "${project_root}" branch --show-current 2>/dev/null || true)"

if [[ -z "${branch}" ]]; then
  branch="master"
fi

if ! brew tap | grep -qx "${tap_name}"; then
  brew tap-new "${tap_name}"
fi

mkdir -p "$(dirname "${formula_target}")"
sed \
  -e "s|head \"https://github.com/leonardwongly/AppleCalendarMCPServer.git\"|head \"file://${project_root}\",\\
       using:  GitDownloadStrategy,|" \
  -e "/using:  GitDownloadStrategy,/a\\
       branch: \"${branch}\"" \
  "${formula_source}" > "${formula_target}"

brew install --HEAD "${tap_name}/apple-calendar-mcp-server" "$@"
