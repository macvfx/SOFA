# SOFA
Use the open source SOFA feed to check if Macs managed with simpleMDM are up to date

## Use SOFA updates list to check SimpleMDM device list and see who needs to update macOS

"[This bash script](simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh)" will fetch SimpleMDM device list using your API key and check if any devices need updates and/or are compatible with the latest macOS. 

Output of the script is the JSON device list, and some CSV files that display data from SimpleMDM compared with the SOFA RSS feed JSON.

Note: When you run the script "simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh" it will ask for your API key with at least read access. It cache the SOFA feed and use this for subsequent script runs unless "--force" is specified to redownload the SOFA feed.

The main script will output:
1) The full SimpleMDM device list in JSON 
2) CSV of the full SimpleMDM device list and matches the macOS with available updates and max supported versions.
3) CSV of just the Macs needing updates
4) CSV of Mac models and what macOS they support

There's also a second script which shows an exmaple of getting data from a SimpleMDM custom atrribute, in this case called "xprotect"

## Usage

Run script to cache download device list and SOFA feed

*bash ./simpleMDM-devices-vs-SOFA-macOS-update-check.sh*

And enter your API key.

Run with "--force" to re-download device list. Important to do this is using a different API key for different devices than already downloaded.

*bash ./simpleMDM-devices-vs-SOFA-macOS-update-check.sh --force*

## Example

*bash ./simpleMDM-devices-vs-SOFA-macOS-update-check.sh*

Enter your SimpleMDM API key: 
Cached SimpleMDM device list is older than a day; will refresh.
Fetching SimpleMDM device list (cursor-style pagination)...
== Fetching page 1 (starting_after='none') ==
Page 1 returned 25 devices; last_id='1654650'; has_more=false
Pagination terminating: has_more='false' or last_id'xxx'.
Total unique devices in use: 25
Cached SOFA feed is older than a day; will refresh.
Downloading SOFA feed...

Fetching SimpleMDM device list...
Downloading SOFA feed...

✅ Exported:
  → Full device CSV: /Users/Shared/simplemdm_devices_full_2025-08-30.csv
  → Outdated devices CSV: /Users/Shared/simplemdm_devices_needing_update_2025-08-30.csv
  → Supported macOS per model: /Users/Shared/simplemdm_supported_macos_models_2025-08-30.csv
✅ Export complete.