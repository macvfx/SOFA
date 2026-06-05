# SimpleMDM + SOFA Security Check Scripts

Bash scripts that use the [SOFA feed](https://sofa.macadmins.io) to check if Macs managed with [SimpleMDM](https://simplemdm.com) are up to date, secure, and running current XProtect definitions.

## Scripts

### 1. Device Security Check
**`simpleMDM-devices-vs-SOFA-macOS-update-check-security-review-lastSEEN.sh`**

Full device inventory and security audit. Fetches all devices from SimpleMDM with pagination, compares against the SOFA feed, checks XProtect versions via custom attributes, and exports:

- **Full CSV** — every device with: name, serial, OS version, latest minor/major, update status, unfixed CVE count, XProtect status, FileVault, SIP, Firewall, recovery key, compatible OS, last seen
- **Needs Update CSV** — only devices behind on OS, with upgrade recommendations and XProtect status
- **Supported Models CSV** — unique hardware models with marketing name and latest compatible macOS
- **JSON** — complete API response

```bash
API_KEY="your-key" ./simpleMDM-devices-vs-SOFA-macOS-update-check-security-review-lastSEEN.sh [--force]
```

### 2. Security Report
**`simpleMDM-security-report.sh`**

Focused security audit that flags only devices with issues. Produces a CSV report and a text summary for client or management reporting.

**Issues flagged:**
- OS outdated — recommends only actively supported macOS versions (e.g., 15 or 26), not EOL releases
- Unfixed CVEs — count computed from SOFA SecurityReleases data
- XProtect outdated — version comparison shown (e.g., "XProtect outdated (5345 → 5347)")
- XProtect invalid — non-numeric custom attribute value
- FileVault disabled
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

All exports are saved to `~/../../Shared/simpleMDM_export/` with timestamps. Files open automatically after export.

**Cache:** API responses and the SOFA feed are cached for 24 hours in `~/../../Shared/simpleMDM_export/API/`. Use `--force` to bypass the cache.

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

The following older scripts are kept for reference but are superseded by the scripts above:

- `simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh` — original basic version
- `simpleMDM-devices-vs-SOFA-macOS-update-check-fv-fw-security-review-lastSEEN.sh` — added FV/FW/SIP
- `simpleMDM-devices-vs-SOFA-macOS-update-check-xprotect-custom-attribute.sh` — added XProtect custom attribute

## Companion App

**[Simple Security Check](https://github.com/macvfx/SimpleSecurityCheck)** — a native macOS SwiftUI app that provides the same functionality with a GUI: device table with colour-coded security indicators, XProtect version monitoring, vulnerability check reports, profiles/scripts/groups browser, and CSV/JSON export.

## Changelog

**v3.1** — Added XProtect version checking to device and security report scripts, unfixed CVE counts, smart upgrade recommendations (only actively supported macOS versions), apps catalog script, and XProtect version check script.

**v2.9** — Added unfixed CVE tracking from SOFA SecurityReleases, upgrade recommendations for actively supported macOS only, replaced plutil with jq.

**v1.0** — Original device check with SOFA comparison, FileVault/SIP/Firewall status, caching, and pagination.
