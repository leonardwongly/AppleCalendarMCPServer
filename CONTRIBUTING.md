# Contributing

## Local validation

Run the same gates used by CI:

```bash
python3 scripts/check_release_consistency.py
swift test
swift build -c release
./scripts/build_app_bundle.sh release
./scripts/build_mac_app.sh release
python3 scripts/smoke_mcp.py --binary .build/arm64-apple-macosx/release/AppleCalendarMCPServer
```

Live calendar tests are opt-in because they touch private local data. A write
probe must create a clearly temporary event, delete it immediately, and verify
cleanup with `scripts/smoke_mcp.py --live-write-probe-calendar-id`.

## Pull requests

Keep changes focused, add regression tests for behavioral fixes, and document
externally visible changes. Never commit calendar data, credentials, signing
certificates, build output, or local MCP configuration.

## Releases

1. Update the canonical version and both app-bundle versions.
2. Run `scripts/check_release_consistency.py` and all validation gates.
3. Merge the release PR and tag the merge commit.
4. Run `scripts/package_release.sh` and attach its artifacts plus `SHA256SUMS`.
5. Compute the tagged source archive checksum.
6. Update both the source formula and the authoritative Homebrew tap by PR.
7. Install from the public tap and rerun MCP and calendar capability checks.
