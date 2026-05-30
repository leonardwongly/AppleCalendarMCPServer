# Apple Calendar MCP

Local macOS MCP server for Apple Calendar built with Swift and `EventKit`.

## Features

- `calendar_list`
- `calendar_events_search`
- `calendar_event_create`
- `calendar_event_update`
- `calendar_event_delete`

## Requirements

- macOS
- Xcode command line tools or Xcode
- Calendar permission granted to the built executable on first access

## Build

```bash
swift build
./scripts/build_app_bundle.sh
```

## Run

```bash
swift run
```

With runtime policy controls:

```bash
APPLE_CALENDAR_MCP_READ_ONLY=true swift run
APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS="calendar-id-1,calendar-id-2" swift run
```

The server uses MCP `stdio` framing and is intended to be launched by an MCP client rather than used manually in a terminal.

To trigger the macOS Calendar permission prompt directly, launch the app bundle in one-shot access-request mode:

```bash
open -W .build/arm64-apple-macosx/debug/AppleCalendarMCPServer.app --args --request-calendar-access
```

If macOS has already stored a denial for this helper, reset only this app's Calendar privacy decision before retrying:

```bash
tccutil reset Calendar com.openai.codex.apple-calendar-mcp
open -W .build/arm64-apple-macosx/debug/AppleCalendarMCPServer.app --args --request-calendar-access
```

If macOS still denies EventKit access, read tools degrade to a local read-only SQLite fallback at:

```text
~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb
```

The fallback only supports `calendar_list` and `calendar_events_search`; calendars returned by this path are reported as not writable, and create/update/delete still require EventKit access.

## Example MCP client config

Adjust the absolute path for your machine:

```json
{
  "mcpServers": {
    "apple-calendar": {
      "command": "/Users/leonardwongly/Developer/AppleCalendarMCPServer/.build/arm64-apple-macosx/debug/AppleCalendarMCPServer.app/Contents/MacOS/AppleCalendarMCPServer",
      "env": {
        "APPLE_CALENDAR_MCP_READ_ONLY": "true"
      }
    }
  }
}
```

## Runtime controls

- `APPLE_CALENDAR_MCP_READ_ONLY`
  Accepts `true/false`, `1/0`, `yes/no`, `on/off`.
  When enabled, create, update, and delete operations are blocked.

- `APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS`
  Comma-separated calendar ID allowlist for write operations.
  When set, write operations are allowed only for those exact calendar IDs.

`calendar_list` reflects these controls by reporting `allowsContentModifications: false` when writes are disabled by policy.

## Tool notes

### `calendar_list`

Returns visible Apple Calendar calendars with stable calendar IDs.

### `calendar_events_search`

Inputs:

- `start` ISO 8601 datetime with timezone
- `end` ISO 8601 datetime with timezone
- `calendarIds` optional array of calendar IDs
- `query` optional case-insensitive text filter

Guardrails:

- rejects unknown fields
- rejects invalid dates
- limits range to 366 days

### `calendar_event_create`

Inputs:

- `calendarId`
- `title`
- `start`
- `end`
- `isAllDay` optional
- `location` optional
- `notes` optional
- `url` optional, `http` or `https` only

### `calendar_event_update`

Inputs:

- `eventId`
- any mutable event field
- `span` optional: `thisEvent` or `futureEvents`

### `calendar_event_delete`

Inputs:

- `eventId`
- `span` optional: `thisEvent` or `futureEvents`

## Validation

```bash
swift test
swift build
./scripts/build_app_bundle.sh
python3 scripts/smoke_mcp.py
```

Optional live calendar read smoke test:

```bash
python3 scripts/smoke_mcp.py --live-calendar-list
```

## Security posture

- local-only `stdio` transport
- no HTTP listener
- strict input validation
- unknown-field rejection
- date-range limit for search
- optional read-only mode
- optional write allowlist by calendar ID
- write operations require a writable target calendar
- URL inputs limited to `http` and `https`

## Known limitations

- recurring event operations are exposed only through `thisEvent` and `futureEvents`
- first live event read/write will trigger macOS Calendar permission prompts when launched from the bundled executable
- event IDs are sourced from `EventKit` and may change if Apple rewrites the underlying item
