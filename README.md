# SOFA
Use the open source SOFA feed to check if Macs managed with simpleMDM are up to date

## Use SOFA updates list to check SimpleMDM device list and see who needs to update macOS

I wrote a "simple" bash script to check SimpleMDM device list by API and check if any devices need updates and/or are compatible with the latest macOS. Of course, it will output some CSVs for fun and profit. Send to clients, managers, security professionals and be well.

Note: It will output:
1) The full SimpleMDM device list in JSON 
2) CSV of the full SimpleMDM device list and matches the macOS with available updates and max supported versions.
3) CSV of just the Macs needing updates
4) CSV of Mac models and what macOS they support

Example:

Fetching SimpleMDM device list...
Downloading SOFA feed...

✅ Exported:
  → Full device CSV: /Users/Shared/simplemdm_devices_full_2025-07-30.csv
  → Outdated devices CSV: /Users/Shared/simplemdm_devices_needing_update_2025-07-30.csv
  → Supported macOS per model: /Users/Shared/simplemdm_supported_macos_models_2025-07-30.csv
✅ Export complete.
