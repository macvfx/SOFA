# TL;DR
Use the open source SOFA feed to check if Macs managed with simpleMDM are up to date
--

# SimpleMDM macOS Device Export Tool

The scripts in this repo export device information from SimpleMDM, check for macOS updates via the SOFA feed, and generate detailed reports.

## Features
- Export full device details to CSV
- Identify devices needing macOS upgrades
- Generate supported macOS versions per device model
- Caching for API responses to reduce redundant calls
- Retry logic for robust API communication

## Prerequisites
- Bash shell (macOS/Linux)
- `jq` JSON processor (**note**: macOS 14 and earlier use `brew install jq`)
- `curl` for API requests
- SimpleMDM API key

## Installation
1. Save script as `simplemdm_export.sh`
2. Make executable:
   ```bash
   chmod +x simplemdm_export.sh
   ```

## Configuration
Set your API key in one of these ways:
1. Environment variable:
   ```bash
   export API_KEY="your_simplemdm_api_key"
   ```
2. Enter interactively when prompted

## Usage
```bash
./simplemdm_export.sh [--force]
```

### Flags
- `--force`: Bypass cache and refresh all data

## Output Files
Generated in `/Users/Shared/simplemdm_export_YYYY-MM-DD_HHMM/`:
1. `simplemdm_devices_full_*.csv` - All devices with complete details
2. `simplemdm_devices_needing_update_*.csv` - Devices requiring OS updates
3. `simplemdm_supported_macos_models_*.csv` - Supported OS versions per model
4. `simplemdm_all_devices_*.json` - Raw device data

## File Details

### Full Device CSV Includes:
- Device name & serial number
- Current OS version
- Update availability status
- Security features (FileVault, SIP, Firewall)
- Last seen timestamp
- Maximum supported macOS version

### Update Required CSV Shows:
- Devices with available OS updates
- Key details for update prioritization

### Supported Models CSV Contains:
- Hardware model information
- Latest compatible macOS version
- Marketing names for devices

## Caching
- API responses cached for 24 hours
- SOFA feed cached for 24 hours
- Use `--force` to ignore cache

## Troubleshooting
**API Key Errors**
- Verify key has Device Read permissions
- Check for typos in key
- Ensure no trailing spaces

**JSON Processing**
- Verify `jq` installation
- Check script permissions

**Network Issues**
- Script includes 5 retry attempts with backoff
- Ensure outgoing HTTPS access to:
  - `a.simplemdm.com`
  - `sofafeed.macadmins.io`

## Example Workflow
1. Run initial export:
   ```bash
   ./simplemdm_export.sh
   ```
2. Review `needs_update` CSV
3. Force refresh next day:
   ```bash
   ./simplemdm_export.sh --force
   ```

## Notes
- Output directories automatically open in Finder
- Script handles pagination for large device lists
- Timestamps in UTC format
--

## Variations

"[This bash script](simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh)" will fetch SimpleMDM device list using your API key and check if any devices need updates and/or are compatible with the latest macOS. 

Other examples add security info (filevault encryption and firewall status) or use of a custom attribute.

## CHANGELOG

Added user-agent string per recommended best practises
