#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def frame(message: dict) -> bytes:
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    return payload + b"\n"


def read_responses(stdout: bytes) -> list[dict]:
    responses: list[dict] = []
    for line in stdout.split(b"\n"):
        stripped = line.strip()
        if not stripped:
            continue
        responses.append(json.loads(stripped.decode("utf-8")))
    return responses


def tool_result_payload(result: dict[str, Any]) -> Any:
    if "structuredContent" in result:
        return result["structuredContent"]

    content = result.get("content") or []
    if (
        content
        and isinstance(content[0], dict)
        and isinstance(content[0].get("text"), str)
    ):
        return json.loads(content[0]["text"])

    return result


def extract_event_id(payload: Any) -> str:
    event = payload.get("event", payload) if isinstance(payload, dict) else {}
    event_id = event.get("id")
    if not isinstance(event_id, str) or not event_id:
        raise RuntimeError(f"calendar_event_create returned no event id: {payload!r}")
    return event_id


def remaining_probe_events(payload: Any, title: str) -> list[dict[str, Any]]:
    events = payload.get("events", payload) if isinstance(payload, dict) else []
    if not isinstance(events, list):
        return []
    return [
        event
        for event in events
        if isinstance(event, dict) and event.get("title") == title
    ]


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
    parser.add_argument(
        "--live-write-probe-calendar-id",
        default=None,
        help="Create and immediately delete a temporary event in this calendar ID.",
    )
    parser.add_argument(
        "--live-write-probe-start",
        default="2026-06-19T06:00:00+08:00",
        help="ISO 8601 start time for the temporary write-probe event.",
    )
    parser.add_argument(
        "--live-write-probe-end",
        default="2026-06-19T06:05:00+08:00",
        help="ISO 8601 end time for the temporary write-probe event.",
    )
    args = parser.parse_args()

    binary = Path(args.binary) if args.binary else resolve_default_binary(project_root)
    if not binary.exists():
        print(f"Binary not found: {binary}", file=sys.stderr)
        return 2

    messages = base_messages()
    request_id = 3

    if args.live_calendar_list:
        messages.append(tool_call(request_id, "calendar_list", {}))
        request_id += 1

    probe_title = "Codex Apple Calendar MCP write probe - delete immediately"
    if args.live_write_probe_calendar_id:
        create_id = request_id
        messages.append(
            tool_call(
                create_id,
                "calendar_event_create",
                {
                    "calendarId": args.live_write_probe_calendar_id,
                    "title": probe_title,
                    "start": args.live_write_probe_start,
                    "end": args.live_write_probe_end,
                    "notes": "Temporary write probe created by smoke_mcp.py and deleted immediately.",
                },
            )
        )
        request_id += 1

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

    if args.live_write_probe_calendar_id:
        create_response = response_for(responses, create_id)
        assert_success(create_response)
        event_id = extract_event_id(tool_result_payload(create_response["result"]))

        delete_response = call_single_tool(binary, "calendar_event_delete", {"eventId": event_id})
        assert_success(delete_response)

        verify_response = call_single_tool(
            binary,
            "calendar_events_search",
            {
                "calendarIds": [args.live_write_probe_calendar_id],
                "start": args.live_write_probe_start,
                "end": args.live_write_probe_end,
                "query": probe_title,
            },
        )
        assert_success(verify_response)
        remaining = remaining_probe_events(tool_result_payload(verify_response["result"]), probe_title)
        if remaining:
            raise RuntimeError(f"Write probe event still exists after delete: {remaining!r}")

        responses.append(
            {
                "id": "write-probe",
                "result": {
                    "calendarId": args.live_write_probe_calendar_id,
                    "createdEventId": event_id,
                    "deleted": True,
                    "cleanupVerified": True,
                    "remainingProbeEvents": 0,
                },
            }
        )

    print(json.dumps(responses, indent=2, sort_keys=True))
    return 0


def base_messages() -> list[dict[str, Any]]:
    return [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "smoke-test", "version": "0"},
            },
        },
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    ]


def tool_call(request_id: int, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "tools/call",
        "params": {
            "name": name,
            "arguments": arguments,
        },
    }


def response_for(responses: list[dict[str, Any]], request_id: int) -> dict[str, Any]:
    for response in responses:
        if response.get("id") == request_id:
            return response
    raise RuntimeError(f"No response for request id {request_id}")


def assert_success(response: dict[str, Any]) -> None:
    if response.get("error"):
        raise RuntimeError(f"JSON-RPC error: {response['error']}")
    result = response.get("result")
    if isinstance(result, dict) and result.get("isError"):
        raise RuntimeError(f"Tool error: {result}")


def call_single_tool(binary: Path, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    messages = base_messages()
    messages.append(tool_call(3, name, arguments))

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
        raise RuntimeError(f"MCP server exited with status {proc.returncode}")

    return response_for(read_responses(stdout), 3)


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
