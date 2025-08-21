# SOFA
Use the open source SOFA feed to check if Macs managed with simpleMDM are up to date

## Use SOFA updates list to check SimpleMDM device list and see who needs to update macOS

"[This bash script](simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh)" will fetch SimpleMDM device list using your API key and check if any devices need updates and/or are compatible with the latest macOS. 

Output of the script is the JSON device list, and some CSV files that display data from SimpleMDM compared with the SOFA RSS feed JSON.

The main script will output:
1) The full SimpleMDM device list in JSON 
2) CSV of the full SimpleMDM device list and matches the macOS with available updates and max supported versions.
3) CSV of just the Macs needing updates
4) CSV of Mac models and what macOS they support

There's also a second script which shows an exmaple of getting data from a SimpleMDM custom atrribute, in this case called "xprotect"

## Usage

Run script to cache download device list and SOFA feed

*bash ./simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh*

And enter your API key.

Run with "--force" to re-download device list. Important to do this is using a different API key for different devices than already downloaded.

*bash ./simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh --force*

## Example

*bash ./simpleMDM-devices-vs-SOFA-macOS-update-check-lastSEEN.sh*

Enter your SimpleMDM API key: 
Cached SimpleMDM device list is older than a day; will refresh.
Fetching SimpleMDM device list (cursor-style pagination)...

Cached SOFA feed is older than a day; will refresh.
Downloading SOFA feed...

Fetching SimpleMDM device list...
Downloading SOFA feed...

✅ Exported:
  → Full device CSV: 
  → Outdated devices CSV: 
  → Supported macOS per model: 
✅ Export complete.