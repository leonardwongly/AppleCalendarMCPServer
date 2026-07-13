# Security Policy

## Supported versions

Security fixes are provided for the latest published release.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature for this repository. Do
not open a public issue containing exploit details, calendar data, credentials,
or private event metadata.

Include the affected version, reproduction steps, impact, and any suggested
mitigation. Reports will be acknowledged as soon as practical.

## Security model

The server is local-only and uses MCP over standard input/output. macOS EventKit
permissions remain authoritative. Write access can additionally be disabled or
restricted by calendar identifier through the documented environment variables.
An explicitly empty write allowlist denies writes to every calendar.
