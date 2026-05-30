# Apple Calendar CLI Interface Design

**Date:** 2026-05-30  
**Status:** Approved  
**Scope:** Add dual-mode CLI interface to existing MCP server

---

## Overview

Extend the existing Apple Calendar MCP server to support direct CLI usage while maintaining full backward compatibility with MCP protocol mode. Users will interact via `ical` command for calendar operations without needing to understand MCP internals.

---

## Architecture

### Dual-Mode Operation

The app detects launch mode automatically:

1. **MCP Mode** (existing, unchanged)
   - Triggered when stdin receives MCP protocol frames
   - Operates on stdio framing as before
   - Suitable for MCP clients (Claude, etc.)

2. **CLI Mode** (new)
   - Triggered when command-line arguments are present
   - Executes requested operation, formats output, exits
   - Suitable for terminal and scripting workflows

### EventKit Access Strategy

**Primary path (MCP Server):**
- If MCP server is running and accessible via IPC, CLI connects to it
- No new EventKit initialization needed
- Shared calendar state

**Fallback path (Direct EventKit):**
- If MCP server unreachable or unavailable, initialize EventKit in-process
- CLI gets fresh access to calendar data
- Slower startup but ensures reliability

**Result:** CLI always works, with graceful degradation

---

## Command Structure

### Pattern
Action-first naming with required and optional parameters:

```
ical <action> <resource> [options] [--json]
```

### Available Commands

#### List Calendars
```bash
ical list calendars [--json]
```
Shows available calendars with IDs, titles, and write permissions.

#### Search Events
```bash
ical search events --calendar ID [--from DATE] [--to DATE] [--query TEXT] [--json]
```
- `--calendar`: Calendar ID (required, can use interactive selection)
- `--from`: ISO 8601 start date (optional, defaults to now)
- `--to`: ISO 8601 end date (optional, defaults to +366 days)
- `--query`: Case-insensitive text filter (optional)
- `--json`: Output as JSON (optional)

#### Create Event
```bash
ical create event [--calendar ID] [--title TEXT] [--start DATETIME] [--end DATETIME] \
                  [--location TEXT] [--url URL] [--all-day] [--notes TEXT] [--json]
```
- Required (prompt if missing): calendar, title, start, end
- Optional (prompt only if missing): location, url, notes
- `--all-day`: Flag to create all-day event (no prompt)
- `--json`: Output created event as JSON

#### Update Event
```bash
ical update event EVENT_ID [--title TEXT] [--start DATETIME] [--end DATETIME] \
                           [--location TEXT] [--url URL] [--notes TEXT] \
                           [--span thisEvent|futureEvents] [--json]
```
- `EVENT_ID`: Event identifier (required)
- `--span`: `thisEvent` (default) or `futureEvents` for recurring events
- All fields optional—only provided ones are updated
- `--json`: Output updated event as JSON

#### Delete Event
```bash
ical delete event EVENT_ID [--span thisEvent|futureEvents] [--json]
```
- `EVENT_ID`: Event identifier (required)
- `--span`: `thisEvent` (default) or `futureEvents` for recurring events
- `--json`: Output deleted event as JSON

---

## Interactive Prompts

When required fields are missing, prompt user in this order:

### Create Event Flow
```
Available calendars:
1) Personal
2) Work
3) Shared Calendar

Select calendar (1-3): 2
Title: Project kickoff meeting
Start date/time (YYYY-MM-DD HH:MM): 2026-06-15 10:00
End date/time (YYYY-MM-DD HH:MM): 2026-06-15 11:00
Location (optional, press Enter to skip): Conference Room A
URL (optional, press Enter to skip): https://example.com/meeting
Notes (optional, press Enter to skip): Initial planning session
```

### Calendar Selection
When `--calendar` not provided to any command requiring it, display numbered list of calendars with descriptions (writable status, etc.).

---

## Output Formatting

### Default (Human-Readable Table)
```
CALENDARS:
Name                 ID                              Writable
────────────────────────────────────────────────────────────
Personal             calendar-1                      Yes
Work                 calendar-2                      Yes
Shared Calendar      calendar-3                      No

EVENTS (3 results):
Title                 Start                   End                     Calendar
──────────────────────────────────────────────────────────────────────────────
Team Standup         2026-06-01 09:00:00    2026-06-01 09:30:00    Work
Project Kickoff      2026-06-01 10:00:00    2026-06-01 11:00:00    Work
Lunch                2026-06-01 12:00:00    2026-06-01 13:00:00    Personal
```

### JSON (`--json` flag)
```json
{
  "calendars": [
    {
      "id": "calendar-1",
      "title": "Personal",
      "allowsContentModifications": true
    }
  ],
  "events": [
    {
      "id": "event-1",
      "title": "Team Standup",
      "start": "2026-06-01T09:00:00+08:00",
      "end": "2026-06-01T09:30:00+08:00",
      "calendar": "Work",
      "location": null,
      "url": null,
      "notes": null,
      "isAllDay": false
    }
  ]
}
```

---

## Build & Installation

### Build Steps
1. Add CLI argument parsing module using Swift's `ArgumentParser` (Vapor/Apple ecosystem standard)
2. Add IPC client to detect and connect to running MCP server
3. Add interactive prompt system for missing fields
4. Add output formatters (table and JSON)
5. Create executable wrapper that detects mode (MCP vs CLI)
6. Reuse existing EventKit service without modification

### Installation
```bash
swift build -c release
sudo cp .build/release/AppleCalendarMCPServer /usr/local/bin/ical
```

### Verify
```bash
ical list calendars
ical --version
ical --help
```

---

## Error Handling

### Exit Codes
- `0`: Success
- `1`: General error (permission denied, calendar not found, EventKit error, etc.)
- `2`: Input validation failed (invalid date format, unknown flag, etc.)
- `127`: Command not found

### User-Facing Errors
```
Error: Calendar 'invalid-id' not found
Available calendars: Personal, Work, Shared Calendar
```

```
Error: Invalid date format. Expected ISO 8601 (YYYY-MM-DDTHH:MM:SS)
```

```
Error: Calendar 'calendar-3' does not allow modifications
```

### MCP Fallback Transparency
Silent fallback to direct EventKit if IPC unavailable. User sees no difference. If both MCP and fallback fail, clear error message:
```
Error: Could not access calendars
- MCP server unavailable
- Direct EventKit access denied (check System Preferences > Privacy & Security > Calendar)
```

---

## Constraints & Guardrails

- Date range limits enforced (max 366 days for search, per existing MCP logic)
- URL validation (http/https only)
- Unknown field rejection (matches MCP server behavior)
- No direct database access—all operations via EventKit or MCP
- Existing permissions controls respected (`APPLE_CALENDAR_MCP_READ_ONLY`, `APPLE_CALENDAR_MCP_WRITABLE_CALENDAR_IDS`)

---

## Testing Strategy

### Unit Tests
- Argument parsing (valid/invalid flags, required fields)
- Output formatters (table and JSON correctness)
- Interactive prompt logic

### Integration Tests
- Create/read/update/delete operations via CLI
- MCP server connection/fallback logic
- Permission enforcement (read-only mode, calendar allowlist)

### Manual Smoke Tests
```bash
ical list calendars
ical search events --calendar Work --from 2026-06-01 --to 2026-06-30
ical create event --calendar Work --title "Test" --start 2026-06-15T10:00 --end 2026-06-15T11:00
ical list calendars --json
```

---

## Implementation Phases

### Phase 1: Scaffolding & Mode Detection
- Add ArgumentParser dependency
- Implement mode detection (MCP vs CLI)
- Add basic help system

### Phase 2: List & Search Commands
- Implement `ical list calendars`
- Implement `ical search events`
- Add table formatter
- Add JSON formatter

### Phase 3: Create/Update/Delete Commands
- Implement `ical create event` with full interactive prompt flow
- Implement `ical update event`
- Implement `ical delete event`

### Phase 4: IPC & Fallback Logic
- Add IPC client to connect to running MCP server
- Implement fallback to direct EventKit
- Add comprehensive error handling

### Phase 5: Polish & Testing
- Comprehensive unit and integration tests
- Installation script
- Documentation updates
- Build release binary
- Smoke test suite

---

## Success Criteria

✅ `ical list calendars` works (table + JSON)  
✅ `ical search events` works with filters  
✅ `ical create event` works with interactive prompts and all fields (title, location, URL)  
✅ `ical update event` works  
✅ `ical delete event` works  
✅ MPC server fallback transparent to user  
✅ All error cases handled with clear messages  
✅ Existing MCP mode unchanged  
✅ Installable as `/usr/local/bin/ical`  
✅ Help system complete (`ical --help`, `ical create event --help`)
