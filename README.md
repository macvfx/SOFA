# SimpleMDM + SOFA Security Check Scripts

Bash scripts that use the [SOFA feed](https://sofa.macadmins.io) to check if Macs managed with [SimpleMDM](https://simplemdm.com) are up to date, secure, and running current XProtect definitions.

## Scripts

### 1. Device Security Check
**`simpleMDM-devices-vs-SOFA-macOS-update-check-security-review-lastSEEN.sh`**

Full device inventory and security audit. Fetches all devices from SimpleMDM with pagination, compares against the SOFA feed, checks XProtect versions via custom attributes, and exports:

- **Full CSV** — every device with FileVault encryption and recovery-key escrow as separate states; recovery-key values are excluded
- **Needs Update CSV** — only devices behind on OS, with upgrade recommendations and XProtect status
- **Supported Models CSV** — unique hardware models with marketing name and latest compatible macOS
- **JSON** — recovery-key-safe device response

```bash
API_KEY="your-key" ./simpleMDM-devices-vs-SOFA-macOS-update-check-security-review-lastSEEN.sh [--force] [--include-recovery-keys]
```

Normal CSV, JSON, response, and cache files remove `filevault_recovery_key`. If an authorized administrator explicitly needs the values, `--include-recovery-keys` implies `--force` and creates a separate `SENSITIVE_simplemdm_filevault_recovery_keys_*.csv` with permissions `0600`. The sensitive file is not opened automatically.

### 2. Security Report
**`simpleMDM-security-report.sh`**

Focused security audit that flags only devices with issues. Produces a CSV report and a text summary for client or management reporting.

**Issues flagged:**
- OS outdated — recommends only actively supported macOS versions (e.g., 15 or 26), not EOL releases
- Unfixed CVEs — count computed from SOFA SecurityReleases data
- XProtect outdated — version comparison shown (e.g., "XProtect outdated (5345 → 5347)")
- XProtect invalid — non-numeric custom attribute value
- FileVault disabled
- FileVault enabled without an escrowed recovery key
- FileVault status unknown
- SIP disabled
- Firewall disabled

**Text summary includes:**
- SOFA XProtect latest versions (Config Data + Framework)
- Count per issue type
- Compliance percentage

```bash
API_KEY="your-key" ./simpleMDM-security-report.sh [--force]
```

### 3. Apps Catalog
**`simpleMDM-apps-catalog.sh`**

Fetches all apps from SimpleMDM with pagination and categorises by installation channel.

**Exports:** All Apps CSV, MDM-only CSV, Munki-only CSV, JSON with summary counts.

```bash
API_KEY="your-key" ./simpleMDM-apps-catalog.sh [--force]
```

**Note:** Requires an API key with app management permissions. Read-only keys return a 403 error.

### 4. XProtect Version Check
**`xprotect-version-check.sh`**

Runs on a Mac to get the local XProtectPlistConfigData version. Optionally pushes it to SimpleMDM as a custom attribute so the other scripts (and the companion app) can compare it against the SOFA feed.

```bash
# Print local XProtect version
./xprotect-version-check.sh
# Output: 5347

# Push to SimpleMDM custom attribute
API_KEY="your-key" DEVICE_ID="12345" ./xprotect-version-check.sh --push
# Output: 5347
#         Pushed xprotect_version=5347 to SimpleMDM device 12345
```

**Deploy via SimpleMDM Scripts** to keep all devices reporting their XProtect version.

## XProtect Monitoring Setup

1. Create a custom attribute in SimpleMDM named `xprotect_version`
2. Deploy `xprotect-version-check.sh` to your devices (via SimpleMDM Scripts)
3. Run the security report or device check — XProtect status will be included automatically

**How matching works:**
The scripts detect any custom attribute with `xprotect` in its name and use smart matching:

| Attribute name contains | Compares against | Example |
|------------------------|------------------|---------|
| `framework` | XProtect Framework | `157` |
| `config` or `plist` | XProtect Config Data | `5347` |
| Just `xprotect` | Auto-detect: 4+ digits = Config Data, 2-3 digits = Framework | `5347` |

## Prerequisites

- macOS with Bash
- `curl`
- `jq` (`brew install jq` on macOS 14 and earlier; included in macOS 15+)
- SimpleMDM API key with device read permissions

## Configuration

Set your API key as an environment variable or enter it interactively when prompted:

```bash
export API_KEY="your_simplemdm_api_key"
```

## Output

Exports are saved to `/Users/Shared/simpleMDM_export/` with timestamps. Ordinary reports open automatically; sensitive recovery-key exports do not.

**Cache:** Recovery-key-safe API responses and the SOFA feed are cached for 24 hours in `/Users/Shared/simpleMDM_export/API/`. Existing caches are sanitized on read. Use `--force` to bypass the cache.

## Recovery Key Safety

- FileVault encryption and FDE recovery-key escrow are reported separately.
- SimpleMDM does not return a separate escrow boolean: non-empty `filevault_recovery_key` is escrowed, explicit null/empty is not escrowed, and an absent field is unknown.
- Ordinary outputs never include recovery-key values.
- The security report flags encrypted Macs whose key is not escrowed.
- A sensitive key inventory is always a separate, explicit, freshly fetched file.
- API response bodies containing device keys are not retained as raw output.

## Optional Intel-only Application Inventory

Use [`SimpleMDM-IntelInventory.sh`](SimpleMDM-IntelInventory.sh) with a SimpleMDM `intel_inventory` custom attribute to identify applications that still require Rosetta. The versioned output includes the Intel-only app count, application names, scan time, and Mac architecture.

See [SimpleMDM Intel Inventory Setup](SimpleMDM-IntelInventory.md) for configuration instructions. Simple Security Check 3.4 and later surfaces this optional data in its Devices table, Device Inspector, Compatibility Risk report, and CSV export.

## Troubleshooting

**API Key Errors**
- Verify key has Device Read permissions in SimpleMDM
- Apps endpoint requires app management permissions (403 = insufficient access)

**Network Issues**
- Scripts include retry logic (5 attempts with exponential backoff)
- Requires HTTPS access to `a.simplemdm.com` and `sofafeed.macadmins.io`

**XProtect not showing**
- Ensure the custom attribute name contains `xprotect` (e.g., `xprotect_version`)
- Value must be a number (not description text)
- Run `xprotect-version-check.sh` on the device to verify

## Legacy Scripts

Older scripts are kept in the `legacy/` folder for reference but are superseded by the scripts above:

- `legacy/simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh` — original basic version
- `legacy/simpleMDM-devices-vs-SOFA-macOS-update-check-fv-fw-security-review-lastSEEN.sh` — added FV/FW/SIP
- `legacy/simpleMDM-devices-vs-SOFA-macOS-update-check-xprotect-custom-attribute.sh` — added XProtect custom attribute

Legacy scripts are historical examples and do not implement the recovery-key protections in version 3.3. Do not use them for production exports.

## Companion App

**Simple Security Check 3.4 (Build 12)** — a native macOS SwiftUI app with FileVault escrow compliance, optional Intel-only application readiness, fleet custom attribute reporting, protected recovery-key workflows, XProtect monitoring, and vulnerability reports. See the [Releases](https://github.com/macvfx/SOFA/releases) section for downloads and release notes.

## Changelog

**v3.4** — Added the optional versioned `intel_inventory` script, scan timestamps and architecture, public setup instructions, and Simple Security Check compatibility reporting guidance.

**v3.3** — Added FileVault recovery-key escrow compliance. Default caches, CSVs, JSON, and response outputs remove key values. Added explicit `--include-recovery-keys` mode with fresh API fetch, `SENSITIVE_` filename, and owner-only permissions. Security reports now flag enabled FileVault without an escrowed key.

**v3.1** — Added XProtect version checking to device and security report scripts, unfixed CVE counts, smart upgrade recommendations (only actively supported macOS versions), apps catalog script, and XProtect version check script.

**v2.9** — Added unfixed CVE tracking from SOFA SecurityReleases, upgrade recommendations for actively supported macOS only, replaced plutil with jq.

**v1.0** — Original device check with SOFA comparison, FileVault/SIP/Firewall status, caching, and pagination.
