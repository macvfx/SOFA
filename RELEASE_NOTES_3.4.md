# Simple Security Check 3.4 - Optional Intel Inventory

Simple Security Check 3.4 (Build 12) can interpret an optional SimpleMDM `intel_inventory` custom attribute without imposing that workflow on every account.

## Public inventory script

- Adds `SimpleMDM-IntelInventory.sh`.
- Reports Intel-only application count and names.
- Adds a version, UTC scan time, and Mac architecture for stale-data detection.
- Prints one line suitable for a SimpleMDM custom attribute.

## App integration

- Devices and Device Inspector surface Intel readiness only when the selected account defines or returns the attribute.
- Compatibility Risk remains discoverable and links to setup instructions when unconfigured.
- Configured accounts receive By Device and By Application views, explicit missing/invalid/stale coverage, newest-last-seen-first defaults, sortable columns, and CSV export.
- Fleet Custom Attributes reporting provides values and missing coverage for all SimpleMDM custom attributes.
- Demo Mode includes deterministic FileVault escrow, Intel inventory, custom-attribute coverage, and Last Seen fixtures for reviewing the new dashboards.
- Force Refresh now bypasses and revalidates both the app's SQLite cache and the HTTP response cache so same-day SOFA updates appear immediately.

See [SimpleMDM Intel Inventory Setup](SimpleMDM-IntelInventory.md).
