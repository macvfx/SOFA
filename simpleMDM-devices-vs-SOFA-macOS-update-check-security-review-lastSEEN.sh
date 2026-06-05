#!/usr/bin/env bash
set -euo pipefail

# simpleMDM-devices-vs-SOFA-macOS-update-check-security-review-lastSEEN.sh
# Fetches all devices from SimpleMDM with pagination, compares against the SOFA
# macOS security feed, and exports:
#   - Full device CSV with all security attributes including unfixed CVE count
#   - Devices needing update CSV
#   - Supported macOS models CSV
#   - Raw JSON export
#
# Usage:
#   ./script.sh [--force]
#   --force : ignore cache age and re-download both SimpleMDM device list and SOFA feed
#
# Set API_KEY env var or you will be prompted.

# ---------- DEPENDENCY CHECKS ----------
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required but not installed." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required. Install with: brew install jq" >&2; exit 1; }

# ---------- OPTIONS ----------
FORCE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

# ---------- CONFIG ----------
API_KEY="${API_KEY:-}"

if [[ -z "$API_KEY" ]]; then
    read -rsp "Enter your SimpleMDM API key: " API_KEY
    echo
fi

DATE=$(date +"%Y-%m-%d_%H%M")
OUTPUT_DIR="/Users/Shared/simpleMDM_export"
CACHE_DIR="${OUTPUT_DIR}/API"
mkdir -p "$CACHE_DIR"

user_agent="SimpleMDMExporter/3.1"

SOFA_JSON="${CACHE_DIR}/macos_data_feed.json"
CACHED_DEVICES_JSON="${CACHE_DIR}/simplemdm_all_devices_cached.json"
FULL_CSV="${OUTPUT_DIR}/simplemdm_devices_full_${DATE}.csv"
NEEDS_UPDATE_CSV="${OUTPUT_DIR}/simplemdm_devices_needing_update_${DATE}.csv"
SUPPORTED_CSV="${OUTPUT_DIR}/simplemdm_supported_macos_models_${DATE}.csv"
ALL_DEVICES_JSON="${OUTPUT_DIR}/simplemdm_all_devices_${DATE}.json"

echo "\"name\",\"device_name\",\"serial\",\"os_version\",\"latest_major_os\",\"needs_update\",\"unfixed_cves\",\"xprotect_status\",\"product_name\",\"filevault_status\",\"filevault_recovery_key\",\"sip_enabled\",\"firewall_enabled\",\"latest_compatible_os\",\"latest_compatible_os_version\",\"last_seen_at\"" > "$FULL_CSV"
echo "\"name\",\"device_name\",\"serial\",\"os_version\",\"latest_major_os\",\"unfixed_cves\",\"xprotect_status\",\"upgrade_recommendation\",\"product_name\",\"filevault_status\",\"last_seen_at\"" > "$NEEDS_UPDATE_CSV"

# ---------- PRECHECK ----------
if [[ -z "${API_KEY:-}" ]]; then
    echo "ERROR: API_KEY is empty. Set it in the script or export it as an env var." >&2
    exit 1
fi

# ---------- 1. FETCH / CACHE SimpleMDM Device List ----------
need_fetch_devices=0
if (( FORCE == 1 )); then
    echo "--force given, will re-fetch SimpleMDM devices."
    need_fetch_devices=1
elif [[ ! -f "$CACHED_DEVICES_JSON" ]]; then
    echo "No cached SimpleMDM device list found; will fetch."
    need_fetch_devices=1
else
    age=$(( $(date +%s) - $(stat -f %m "$CACHED_DEVICES_JSON") ))
    if (( age >= 86400 )); then
        echo "Cached SimpleMDM device list is older than a day; will refresh."
        need_fetch_devices=1
    else
        echo "Using cached SimpleMDM device list (age ${age}s)."
    fi
fi

if (( need_fetch_devices == 1 )); then
    echo "Fetching SimpleMDM device list (cursor-style pagination)..."
    LIMIT=100
    starting_after=""
    all_devices="[]"
    page=1

    while :; do
        if [[ -z "$starting_after" ]]; then
            url="https://a.simplemdm.com/api/v1/devices?limit=${LIMIT}"
        else
            url="https://a.simplemdm.com/api/v1/devices?limit=${LIMIT}&starting_after=${starting_after}"
        fi

        echo "== Fetching page $page (starting_after='${starting_after:-none}') =="
        attempt=0
        max_attempts=5
        backoff=1
        resp_body=""
        while :; do
            raw=$(curl -sS -u "${API_KEY}:" -A "$user_agent" -w "\n%{http_code}" "$url" || true)
            http_code=$(printf '%s' "$raw" | tail -1)
            body=$(printf '%s' "$raw" | sed '$d')

            if [[ "$http_code" == "200" ]] && echo "$body" | jq -e '.data' &>/dev/null; then
                resp_body="$body"
                break
            fi

            echo "Fetch attempt $((attempt+1)) failed (HTTP $http_code)."
            printf '%s\n' "$body" | head -c 800

            attempt=$((attempt + 1))
            if (( attempt >= max_attempts )); then
                echo "ERROR: giving up after $attempt attempts on URL: $url" >&2
                printf '%s\n' "$body" >&2
                exit 1
            fi
            echo "Retrying in $backoff seconds..."
            sleep "$backoff"
            backoff=$(( backoff * 2 ))
        done

        data_array=$(echo "$resp_body" | jq '.data')
        count=$(echo "$data_array" | jq 'length')
        last_id=$(echo "$data_array" | jq -r '.[-1].id // empty')
        has_more=$(echo "$resp_body" | jq -r '.has_more // "false"')
        echo "Page $page returned $count devices; last_id='$last_id'; has_more=$has_more"

        all_devices=$(jq -s '.[0] + .[1]' <(echo "$all_devices") <(echo "$data_array"))

        if [[ "$has_more" != "true" || -z "$last_id" ]]; then
            echo "Pagination terminating: has_more='$has_more' or last_id='$last_id'."
            break
        fi

        starting_after="$last_id"
        ((page++))
    done

    all_devices_deduped=$(echo "$all_devices" | jq 'unique_by(.id)')
    echo "{\"data\":$all_devices_deduped}" > "$CACHED_DEVICES_JSON"
else
    echo "Loading devices from cache."
    all_devices_deduped=$(jq '.data' "$CACHED_DEVICES_JSON")
fi

response="{\"data\":$all_devices_deduped}"
echo "Total unique devices in use: $(echo "$all_devices_deduped" | jq 'length')"
echo "$all_devices_deduped" | jq . > "$ALL_DEVICES_JSON"

# ---------- 2. FETCH / CACHE SOFA FEED ----------
need_fetch_sofa=0
if (( FORCE == 1 )); then
    echo "--force given, will re-download SOFA feed."
    need_fetch_sofa=1
elif [[ ! -f "$SOFA_JSON" ]]; then
    echo "No cached SOFA feed found; will download."
    need_fetch_sofa=1
else
    age=$(( $(date +%s) - $(stat -f %m "$SOFA_JSON") ))
    if (( age >= 86400 )); then
        echo "Cached SOFA feed is older than a day; will refresh."
        need_fetch_sofa=1
    else
        echo "Using cached SOFA feed (age ${age}s)."
    fi
fi

if (( need_fetch_sofa == 1 )); then
    echo "Downloading SOFA feed..."
    curl -s "https://sofafeed.macadmins.io/v1/macos_data_feed.json" -A "$user_agent" -o "$SOFA_JSON"
else
    echo "Loaded SOFA feed from cache."
fi

# ---------- 3. BUILD LATEST OS LOOKUP & CVE INDEX ----------
declare -A latest_os_by_major
os_versions_count=$(jq '.OSVersions | length' "$SOFA_JSON")

for (( i=0; i<os_versions_count; i++ )); do
    product_version=$(jq -r ".OSVersions[$i].Latest.ProductVersion // empty" "$SOFA_JSON")
    if [[ -n "$product_version" ]]; then
        major=$(echo "$product_version" | cut -d'.' -f1)
        latest_os_by_major["$major"]="$product_version"
    fi
done

# Find the two newest major versions (actively supported)
active_majors=$(printf '%s\n' "${!latest_os_by_major[@]}" | sort -n | tail -2)

# Build CVE index per major version
CVE_INDEX_DIR=$(mktemp -d)
for (( i=0; i<os_versions_count; i++ )); do
    major=$(jq -r ".OSVersions[$i].Latest.ProductVersion // empty" "$SOFA_JSON" | cut -d'.' -f1)
    [[ -z "$major" ]] && continue
    jq -r ".OSVersions[$i].SecurityReleases // [] | .[] | \"\(.ProductVersion)\t\(.CVEs // {} | keys | join(\",\"))\"" "$SOFA_JSON" > "${CVE_INDEX_DIR}/releases_${major}.tsv" 2>/dev/null || true
done

# Get latest XProtect versions from SOFA
SOFA_XP_CONFIG=$(jq -r '.XProtectPlistConfigData."com.apple.XProtect" // empty' "$SOFA_JSON")
SOFA_XP_FRAMEWORK=$(jq -r '.XProtectPayloads."com.apple.XProtectFramework.XProtect" // empty' "$SOFA_JSON")
echo "SOFA XProtect Config Data: ${SOFA_XP_CONFIG:-unknown}"
echo "SOFA XProtect Framework: ${SOFA_XP_FRAMEWORK:-unknown}"

# Fetch XProtect custom attribute for a device
get_xprotect_status() {
    local device_id="$1"
    local resp
    resp=$(curl -sS -u "${API_KEY}:" -A "$user_agent" \
        "https://a.simplemdm.com/api/v1/devices/${device_id}/custom_attribute_values" 2>/dev/null || true)
    [[ -z "$resp" ]] && echo "n/a" && return

    local xp_values
    xp_values=$(echo "$resp" | jq -r '.data[]? | select(.id | ascii_downcase | contains("xprotect")) | "\(.id)\t\(.attributes.value // "")"' 2>/dev/null || true)
    [[ -z "$xp_values" ]] && echo "n/a" && return

    while IFS=$'\t' read -r attr_id attr_value; do
        local clean_val
        clean_val=$(echo "$attr_value" | sed 's/ *(.*//;s/^ *//;s/ *$//')
        [[ -z "$clean_val" ]] && continue
        if ! [[ "$clean_val" =~ ^[0-9]+$ ]]; then
            echo "invalid" && return
        fi

        local latest=""
        local lower_id
        lower_id=$(echo "$attr_id" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_id" == *"framework"* ]]; then
            latest="$SOFA_XP_FRAMEWORK"
        elif [[ "$lower_id" == *"config"* || "$lower_id" == *"plist"* ]]; then
            latest="$SOFA_XP_CONFIG"
        elif (( clean_val >= 1000 )); then
            latest="$SOFA_XP_CONFIG"
        else
            latest="$SOFA_XP_FRAMEWORK"
        fi

        if [[ -n "$latest" && "$clean_val" != "$latest" ]]; then
            echo "outdated" && return
        fi
    done <<< "$xp_values"
    echo "current"
}

# Version comparison: returns 0 (true) if $1 > $2
version_gt() {
    local IFS='.'
    local -a a=($1) b=($2)
    local max=$(( ${#a[@]} > ${#b[@]} ? ${#a[@]} : ${#b[@]} ))
    for (( j=0; j<max; j++ )); do
        local av="${a[j]:-0}" bv="${b[j]:-0}"
        (( av > bv )) && return 0
        (( av < bv )) && return 1
    done
    return 1
}

count_unfixed_cves() {
    local device_version="$1"
    local major="$2"
    local releases_file="${CVE_INDEX_DIR}/releases_${major}.tsv"

    [[ ! -f "$releases_file" ]] && echo "0" && return

    local device_cves=""
    device_cves=$(awk -F'\t' -v ver="$device_version" '$1 == ver { print $2 }' "$releases_file")

    local all_newer_cves=""
    while IFS=$'\t' read -r rel_version rel_cves; do
        if version_gt "$rel_version" "$device_version"; then
            if [[ -n "$rel_cves" ]]; then
                [[ -n "$all_newer_cves" ]] && all_newer_cves="${all_newer_cves},${rel_cves}"
                [[ -z "$all_newer_cves" ]] && all_newer_cves="$rel_cves"
            fi
        fi
    done < "$releases_file"

    [[ -z "$all_newer_cves" ]] && echo "0" && return

    local missing
    if [[ -z "$device_cves" ]]; then
        missing=$(echo "$all_newer_cves" | tr ',' '\n' | sort -u | wc -l | tr -d ' ')
    else
        missing=$(comm -23 <(echo "$all_newer_cves" | tr ',' '\n' | sort -u) <(echo "$device_cves" | tr ',' '\n' | sort -u) | wc -l | tr -d ' ')
    fi
    echo "$missing"
}

get_upgrade_recommendation() {
    local current_major="$1"
    local product_name="$2"

    local compat_os
    compat_os=$(jq -r ".Models[\"$product_name\"].SupportedOS[0] // empty" "$SOFA_JSON" 2>/dev/null || true)
    local compat_major=""
    if [[ -n "$compat_os" ]]; then
        for (( i=0; i<os_versions_count; i++ )); do
            local os_name
            os_name=$(jq -r ".OSVersions[$i].OSVersion // empty" "$SOFA_JSON")
            if [[ "$os_name" == "$compat_os" ]]; then
                compat_major=$(jq -r ".OSVersions[$i].Latest.ProductVersion // empty" "$SOFA_JSON" | cut -d'.' -f1)
                break
            fi
        done
    fi

    [[ -z "$compat_major" ]] && return

    local recommendations=""
    for m in $active_majors; do
        if (( m > current_major && m <= compat_major )); then
            local ver="${latest_os_by_major[$m]:-}"
            [[ -n "$ver" ]] && recommendations="${recommendations:+$recommendations or }macOS $ver"
        fi
    done

    [[ -n "$recommendations" ]] && echo "$recommendations"
}

# ---------- 4. PROCESS DEVICES ----------
total_count=$(echo "$response" | jq '.data | length')
device_index=0
echo "$response" | jq -c '.data[]' | while read -r device; do
    device_index=$((device_index + 1))
    device_id=$(echo "$device" | jq -r '.id')
    name=$(echo "$device" | jq -r '.attributes.name // empty')
    device_name=$(echo "$device" | jq -r '.attributes.device_name // empty')
    serial=$(echo "$device" | jq -r '.attributes.serial_number // empty')
    os_version=$(echo "$device" | jq -r '.attributes.os_version // empty')
    product_name=$(echo "$device" | jq -r '.attributes.product_name // empty')

    echo "  Processing device $device_index/$total_count: $name"

    filevault_status=$(echo "$device" | jq -r '.attributes.filevault_enabled // empty')
    filevault_recovery_key=$(echo "$device" | jq -r '.attributes.filevault_recovery_key // empty')
    sip_enabled=$(echo "$device" | jq -r '.attributes.system_integrity_protection_enabled // empty')
    firewall_enabled=$(echo "$device" | jq -r '.attributes.firewall.enabled // empty')

    last_seen_at=$(echo "$device" | jq -r '.attributes.last_seen_at // empty')
    last_seen_at_fmt=""
    if [[ -n "$last_seen_at" ]]; then
        last_seen_at_fmt=$(date -j -f "%Y-%m-%dT%H:%M:%S.%NZ" "$last_seen_at" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$last_seen_at")
    fi

    os_major=$(echo "$os_version" | cut -d'.' -f1)
    latest_major_os="${latest_os_by_major[$os_major]:-}"

    needs_update="no"
    if [[ -n "$latest_major_os" && -n "$os_version" && "$latest_major_os" != "$os_version" ]]; then
        needs_update="yes"
    fi

    # Count unfixed CVEs
    unfixed_cves=0
    if [[ -n "$os_version" && -n "$os_major" ]]; then
        unfixed_cves=$(count_unfixed_cves "$os_version" "$os_major")
    fi

    # Check XProtect
    xp_status=$(get_xprotect_status "$device_id")

    # Get compatible OS info via jq
    latest_compatible_os=$(jq -r ".Models[\"$product_name\"].SupportedOS[0] // empty" "$SOFA_JSON" 2>/dev/null || true)
    latest_compatible_os_version=""
    if [[ -n "$latest_compatible_os" ]]; then
        for (( i=0; i<os_versions_count; i++ )); do
            os_ver=$(jq -r ".OSVersions[$i].OSVersion // empty" "$SOFA_JSON")
            if [[ "$os_ver" == "$latest_compatible_os" ]]; then
                latest_compatible_os_version=$(jq -r ".OSVersions[$i].Latest.ProductVersion // empty" "$SOFA_JSON")
                break
            fi
        done
    fi

    echo "\"$name\",\"$device_name\",\"$serial\",\"$os_version\",\"$latest_major_os\",\"$needs_update\",\"$unfixed_cves\",\"$xp_status\",\"$product_name\",\"$filevault_status\",\"$filevault_recovery_key\",\"$sip_enabled\",\"$firewall_enabled\",\"$latest_compatible_os\",\"$latest_compatible_os_version\",\"$last_seen_at_fmt\"" >> "$FULL_CSV"

    if [[ "$needs_update" == "yes" ]]; then
        upgrade_rec=$(get_upgrade_recommendation "$os_major" "$product_name")
        echo "\"$name\",\"$device_name\",\"$serial\",\"$os_version\",\"$latest_major_os\",\"$unfixed_cves\",\"$xp_status\",\"${upgrade_rec:-}\",\"$product_name\",\"$filevault_status\",\"$last_seen_at_fmt\"" >> "$NEEDS_UPDATE_CSV"
    fi
done

# Cleanup CVE index
rm -rf "$CVE_INDEX_DIR"

# ---------- 5. Export Supported macOS per Model ----------
echo "\"product_name\",\"marketing_name\",\"latest_compatible_os\",\"latest_compatible_os_version\"" > "$SUPPORTED_CSV"
product_names=$(echo "$response" | jq -r '.data[].attributes.product_name' | sort -u | grep -v null || true)

for model in $product_names; do
    latest_compatible_os=$(jq -r ".Models[\"$model\"].SupportedOS[0] // empty" "$SOFA_JSON" 2>/dev/null || true)
    [[ -z "$latest_compatible_os" ]] && continue

    latest_compatible_os_version=""
    for (( i=0; i<os_versions_count; i++ )); do
        os_ver=$(jq -r ".OSVersions[$i].OSVersion // empty" "$SOFA_JSON")
        if [[ "$os_ver" == "$latest_compatible_os" ]]; then
            latest_compatible_os_version=$(jq -r ".OSVersions[$i].Latest.ProductVersion // empty" "$SOFA_JSON")
            break
        fi
    done

    marketing_name=$(jq -r ".Models[\"$model\"].MarketingName // empty" "$SOFA_JSON" 2>/dev/null || true)
    echo "\"$model\",\"$marketing_name\",\"$latest_compatible_os\",\"$latest_compatible_os_version\"" >> "$SUPPORTED_CSV"
done

# ---------- DONE ----------
echo "$response" > "${OUTPUT_DIR}/simplemdm_raw_response_${DATE}.json"
echo "✅ Exported:"
echo "  → Full device CSV: $FULL_CSV"
echo "  → Outdated devices CSV: $NEEDS_UPDATE_CSV"
echo "  → Supported macOS per model: $SUPPORTED_CSV"
echo "  → All devices JSON: $ALL_DEVICES_JSON"
open "$FULL_CSV"
open "$NEEDS_UPDATE_CSV"
open "$SUPPORTED_CSV"
open "$ALL_DEVICES_JSON"
echo "✅ Export complete."
