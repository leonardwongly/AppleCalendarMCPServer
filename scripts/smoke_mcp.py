#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def frame(message: dict) -> bytes:
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    return f"Content-Length: {len(payload)}\r\n\r\n".encode("utf-8") + payload


def read_responses(stdout: bytes) -> list[dict]:
    responses: list[dict] = []
    cursor = 0
    marker = b"\r\n\r\n"

    while cursor < len(stdout):
        boundary = stdout.find(marker, cursor)
        if boundary == -1:
            break
        headers = stdout[cursor:boundary].decode("utf-8")
        content_length = None
        for line in headers.split("\r\n"):
            if line.lower().startswith("content-length:"):
                content_length = int(line.split(":", 1)[1].strip())
                break
        if content_length is None:
            raise RuntimeError("Missing Content-Length in server response")
        body_start = boundary + len(marker)
        body_end = body_start + content_length
        responses.append(json.loads(stdout[body_start:body_end].decode("utf-8")))
        cursor = body_end

    return responses


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Smoke-test the Apple Calendar MCP stdio server.")
    parser.add_argument(
        "--binary",
        default=None,
        help="Path to the built AppleCalendarMCPServer binary.",
    )
    parser.add_argument(
        "--live-calendar-list",
        action="store_true",
        help="Also call calendar_list. This may trigger a macOS Calendar permission prompt.",
    )
    args = parser.parse_args()

    binary = Path(args.binary) if args.binary else resolve_default_binary(project_root)
    if not binary.exists():
        print(f"Binary not found: {binary}", file=sys.stderr)
        return 2

    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    ]
    if args.live_calendar_list:
        messages.append({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "calendar_list", "arguments": {}}})

    proc = subprocess.Popen(
        [str(binary)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=os.environ.copy(),
    )

    assert proc.stdin is not None
    for message in messages:
        proc.stdin.write(frame(message))
    proc.stdin.close()

    stdout, stderr = proc.communicate(timeout=10)
    if proc.returncode not in (0, None):
        sys.stderr.write(stderr.decode("utf-8", errors="replace"))
        return proc.returncode

    responses = read_responses(stdout)
    print(json.dumps(responses, indent=2, sort_keys=True))
    return 0

def resolve_default_binary(project_root: Path) -> Path:
    candidates = [
        project_root / ".build" / "debug" / "AppleCalendarMCPServer.app" / "Contents" / "MacOS" / "AppleCalendarMCPServer",
        project_root / ".build" / "arm64-apple-macosx" / "debug" / "AppleCalendarMCPServer.app" / "Contents" / "MacOS" / "AppleCalendarMCPServer",
        project_root / ".build" / "x86_64-apple-macosx" / "debug" / "AppleCalendarMCPServer.app" / "Contents" / "MacOS" / "AppleCalendarMCPServer",
        project_root / ".build" / "debug" / "AppleCalendarMCPServer",
        project_root / ".build" / "arm64-apple-macosx" / "debug" / "AppleCalendarMCPServer",
        project_root / ".build" / "x86_64-apple-macosx" / "debug" / "AppleCalendarMCPServer",
    ]

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return candidates[0]


if __name__ == "__main__":
    raise SystemExit(main())
