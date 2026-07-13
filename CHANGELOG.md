# Changelog

All notable changes are documented here. Versions follow semantic versioning.

## 1.2.1 - 2026-07-13

### Security

- Enforce the 1 MiB stdio limit for every newline-delimited MCP message when a
  single read contains multiple requests.

### Fixed

- Quote release-script helper paths so packaging also works from directories
  whose names contain spaces.

## 1.2.0 - 2026-07-13

### Security

- Make an explicitly empty writable-calendar allowlist deny all writes instead
  of silently allowing every writable calendar.
- Default fresh ACP management-app settings to read-only while preserving
  existing persisted user choices.

### Added

- Support stable MCP protocol revision `2025-11-25`.
- Allow MCP callers to clear event location, notes, and URL with JSON `null`.
- Add CLI `--clear-location`, `--clear-notes`, and `--clear-url` options.
- Bound search responses to 1000 events by default (configurable up to 5000)
  and reject MCP stdio messages larger than 1 MiB.
- Add continuous integration, release-consistency checks, artifact packaging,
  a security policy, and contributor/release documentation.

### Changed

- Return invalid arguments for known tools as MCP tool errors so clients can
  correct calls without treating them as JSON-RPC transport failures.

## 1.1.0 - 2026-07-06

- Add the ACP SwiftUI management app, calendar colors, keyboard shortcuts, and
  an application icon.

## 1.0.3 - 2026-06-18

- Add reusable live create/delete/search validation and publish the stable
  Homebrew formula.
