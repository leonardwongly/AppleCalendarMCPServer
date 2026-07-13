#!/usr/bin/env python3
"""Fail when the source version and generated bundle metadata drift."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent


def require_version(path: str, pattern: str) -> str:
    text = (ROOT / path).read_text(encoding="utf-8")
    match = re.search(pattern, text)
    if not match:
        raise RuntimeError(f"Could not find version in {path}")
    return match.group(1)


def main() -> int:
    versions = {
        "CLIHelpSystem.swift": require_version(
            "Sources/AppleCalendarMCPServer/CLIHelpSystem.swift",
            r'static let version = "([0-9]+\.[0-9]+\.[0-9]+)"',
        ),
        "build_app_bundle.sh": require_version(
            "scripts/build_app_bundle.sh",
            r"CFBundleShortVersionString</key>\s*<string>([^<]+)</string>",
        ),
        "build_mac_app.sh": require_version(
            "scripts/build_mac_app.sh",
            r"CFBundleShortVersionString</key>\s*<string>([^<]+)</string>",
        ),
    }
    unique = set(versions.values())
    if len(unique) != 1:
        for source, version in versions.items():
            print(f"{source}: {version}", file=sys.stderr)
        return 1
    print(f"release version: {unique.pop()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
