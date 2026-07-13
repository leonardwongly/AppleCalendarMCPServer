#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
version="$(sed -n 's/.*static let version = "\([0-9.]*\)".*/\1/p' "${project_root}/Sources/AppleCalendarMCPServer/CLIHelpSystem.swift")"
architecture="$(uname -m)"
output_dir="${project_root}/dist/v${version}"

if [[ -z "${version}" ]]; then
  echo "Unable to determine release version" >&2
  exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

(cd "${project_root}" && swift build -c release)
helper_binary="$("${script_dir}/build_app_bundle.sh" release)"
acp_bundle="$("${script_dir}/build_mac_app.sh" release | tail -1)"
release_dir="$(dirname "$(dirname "$(dirname "$(dirname "${helper_binary}")")")")"
server_binary="${release_dir}/AppleCalendarMCPServer"

cp "${server_binary}" "${output_dir}/ical"
chmod 755 "${output_dir}/ical"

ditto -c -k --sequesterRsrc --keepParent "${acp_bundle}" \
  "${output_dir}/ACP-v${version}-macos-${architecture}.zip"
ditto -c -k --sequesterRsrc --keepParent "${release_dir}/AppleCalendarMCPServer.app" \
  "${output_dir}/AppleCalendarMCPServer-v${version}-macos-${architecture}.zip"
tar -C "${output_dir}" -czf "${output_dir}/ical-v${version}-macos-${architecture}.tar.gz" ical
rm "${output_dir}/ical"

(
  cd "${output_dir}"
  shasum -a 256 ./*.zip ./*.tar.gz > SHA256SUMS
)

codesign --verify --deep --strict "${acp_bundle}"
codesign --verify --deep --strict "${release_dir}/AppleCalendarMCPServer.app"
printf '%s\n' "${output_dir}"
