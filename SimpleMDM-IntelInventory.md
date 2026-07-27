# SimpleMDM Intel Inventory Setup

`SimpleMDM-IntelInventory.sh` reports Intel-only macOS applications that require Rosetta. Its single-line output is designed for a SimpleMDM custom attribute and for the optional Compatibility Risk dashboard in Simple Security Check 3.4 or later.

## Configure SimpleMDM

1. Create a custom attribute named `intel_inventory`.
2. Upload `SimpleMDM-IntelInventory.sh` under **Scripts**.
3. Create a Script Job for the target Macs.
4. Configure the job to store script output in the `intel_inventory` custom attribute.
5. Run it on a schedule appropriate for software changes in your fleet.

The output is versioned and includes collection time and Mac architecture:

```text
v=2;count=3;apps=Example App,Legacy Tool,Old Utility;scanned_at=2026-07-27T18:00:00Z;arch=arm64
```

`count=0;apps=none` means the completed scan found no Intel-only applications. A missing attribute value is different: it means the device has not reported inventory. Simple Security Check also marks inventory older than 30 days as stale.

## Data shown in Simple Security Check

When the attribute exists, the app enables:

- A compact Intel indicator in the Devices table.
- An Apple Silicon Readiness section in Device Inspector.
- Compatibility Risk reporting by device and by application.
- CSV export with device, application, scan-time, architecture, and last-seen evidence.

The feature remains hidden from the Devices table and Inspector for SimpleMDM accounts that do not configure the attribute.
