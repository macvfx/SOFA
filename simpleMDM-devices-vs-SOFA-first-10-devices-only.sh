#!/bin/bash

# ---------- CONFIG ----------
API_KEY="Add Your API key to read device info here"
DATE=$(date +"%Y-%m-%d")
OUTPUT_DIR="/Users/Shared"

SOFA_JSON="${OUTPUT_DIR}/sofa_feed_${DATE}.json"
FULL_CSV="${OUTPUT_DIR}/simplemdm_devices_full_${DATE}.csv"
NEEDS_UPDATE_CSV="${OUTPUT_DIR}/simplemdm_devices_needing_update_${DATE}.csv"
SUPPORTED_CSV="${OUTPUT_DIR}/simplemdm_supported_macos_models_${DATE}.csv"

# Write headers to CSV files
echo "\"name\",\"device_name\",\"serial\",\"os_version\",\"latest_major_os\",\"needs_update\",\"product_name\",\"latest_compatible_os\",\"latest_compatible_os_version\"" > "$FULL_CSV"
echo "\"name\",\"device_name\",\"serial\",\"os_version\",\"latest_major_os\",\"product_name\"" >> "$NEEDS_UPDATE_CSV"

# ---------- 1. FETCH SimpleMDM Device Data ----------
echo "Fetching SimpleMDM device list..."
response=$(curl -s -u "${API_KEY}:" "https://a.simplemdm.com/api/v1/devices")

# ---------- 2. FETCH SOFA Feed ----------
echo "Downloading SOFA feed..."
curl -s "https://sofafeed.macadmins.io/v1/macos_data_feed.json" -o "$SOFA_JSON"

# ---------- 3. Get Latest macOS Version by Major (13/14/15) ----------
declare -A latest_os_by_major

for i in {0..10}; do
    os_version=$(/usr/bin/plutil -extract "OSVersions.$i.OSVersion" raw "$SOFA_JSON" 2>/dev/null)
    product_version=$(/usr/bin/plutil -extract "OSVersions.$i.Latest.ProductVersion" raw "$SOFA_JSON" 2>/dev/null)

    if [[ $os_version && $product_version ]]; then
        major=$(echo "$product_version" | cut -d'.' -f1)
        latest_os_by_major["$major"]="$product_version"
    fi
done

export SOFA_JSON
export FULL_CSV
export NEEDS_UPDATE_CSV
export -f

echo "$response" | jq -c '.data[]' | while read -r device; do
    name=$(echo "$device" | jq -r '.attributes.name')
    device_name=$(echo "$device" | jq -r '.attributes.device_name')
    serial=$(echo "$device" | jq -r '.attributes.serial_number')
    os_version=$(echo "$device" | jq -r '.attributes.os_version')
    product_name=$(echo "$device" | jq -r '.attributes.product_name')

    os_major=$(echo "$os_version" | cut -d'.' -f1)
    latest_major_os="${latest_os_by_major[$os_major]}"

    # Compare versions
    needs_update="no"
    if [[ $latest_major_os && $os_version && $latest_major_os != "$os_version" ]]; then
        needs_update="yes"
    fi

    # 6. Get SupportedOS[0] for product_name
    latest_compatible_os=$(/usr/bin/plutil -extract "Models.$product_name.SupportedOS.0" raw -expect string "$SOFA_JSON" 2>/dev/null)
    latest_compatible_os_version=""
    if [[ -n "$latest_compatible_os" ]]; then
        for i in {0..10}; do
            os_ver=$(/usr/bin/plutil -extract "OSVersions.$i.OSVersion" raw "$SOFA_JSON" 2>/dev/null)
            if [[ "$os_ver" == "$latest_compatible_os" ]]; then
                latest_compatible_os_version=$(/usr/bin/plutil -extract "OSVersions.$i.Latest.ProductVersion" raw "$SOFA_JSON" 2>/dev/null)
                break
            fi
        done
    fi

    # Write full device info
    echo "\"$name\",\"$device_name\",\"$serial\",\"$os_version\",\"$latest_major_os\",\"$needs_update\",\"$product_name\",\"$latest_compatible_os\",\"$latest_compatible_os_version\"" >> "$FULL_CSV"

    # Write filtered outdated
    if [[ "$needs_update" == "yes" ]]; then
        echo "\"$name\",\"$device_name\",\"$serial\",\"$os_version\",\"$latest_major_os\",\"$product_name\"" >> "$NEEDS_UPDATE_CSV"
    fi
done

# ---------- 7. Export Supported macOS per Model ----------
echo "product_name,marketing_name,latest_compatible_os,latest_compatible_os_version" > "$SUPPORTED_CSV"
product_names=$(echo "$response" | jq -r '.data[].attributes.product_name' | sort -u | grep -v null)

for model in $product_names; do
  latest_compatible_os=$(/usr/bin/plutil -extract "Models.$model.SupportedOS.0" raw -expect string "$SOFA_JSON" 2>/dev/null)
  [[ -z "$latest_compatible_os" ]] && continue

  latest_compatible_os_version=""
  for i in {0..10}; do
    os_ver=$(/usr/bin/plutil -extract "OSVersions.$i.OSVersion" raw "$SOFA_JSON" 2>/dev/null)
    if [[ "$os_ver" == "$latest_compatible_os" ]]; then
        latest_compatible_os_version=$(/usr/bin/plutil -extract "OSVersions.$i.Latest.ProductVersion" raw "$SOFA_JSON" 2>/dev/null)
        break
    fi
  done

  marketing_name=$(/usr/bin/plutil -extract "Models.$model.MarketingName" raw "$SOFA_JSON" 2>/dev/null)
  echo "\"$model\",\"$marketing_name\",\"$latest_compatible_os\",\"$latest_compatible_os_version\"" >> "$SUPPORTED_CSV"
done

# ---------- DONE ----------
echo "✅ Exported:"
echo "  → Full device CSV: $FULL_CSV"
echo "  → Outdated devices CSV: $NEEDS_UPDATE_CSV"
echo "  → Supported macOS per model: $SUPPORTED_CSV"
open "$FULL_CSV"
open "$NEEDS_UPDATE_CSV"
open "$SUPPORTED_CSV"
echo "✅ Export complete."  
