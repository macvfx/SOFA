#!/usr/bin/env bash
set -euo pipefail

# ---------- USAGE ----------
# ./script.sh [--force]
#   --force : ignore cache age and re-download both SimpleMDM device list and SOFA feed

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

# ---------- CONFIG ----------
#API_KEY="add key"  # <<< set your token here, export it before running or add it interactively
API_KEY="${API_KEY:-}"

if [[ -z "$API_KEY" ]]; then
    read -rsp "Enter your SimpleMDM API key: " API_KEY
    echo
fi

DATE=$(date +"%Y-%m-%d_%H%M")
OUTPUT_DIR="/Users/Shared"
CACHE_DIR="${OUTPUT_DIR}/API"
mkdir -p "$CACHE_DIR"

SOFA_JSON="${CACHE_DIR}/macos_data_feed.json"
CACHED_DEVICES_JSON="${CACHE_DIR}/simplemdm_all_devices_cached.json"
FULL_CSV="${OUTPUT_DIR}/simplemdm_devices_full_${DATE}.csv"
NEEDS_UPDATE_CSV="${OUTPUT_DIR}/simplemdm_devices_needing_update_${DATE}.csv"
SUPPORTED_CSV="${OUTPUT_DIR}/simplemdm_supported_macos_models_${DATE}.csv"
ALL_DEVICES_JSON="${OUTPUT_DIR}/simplemdm_all_devices_${DATE}.json"

# headers
echo "\"name\",\"device_name\",\"serial\",\"os_version\",\"latest_major_os\",\"needs_update\",\"product_name\",\"latest_compatible_os\",\"latest_compatible_os_version\"" > "$FULL_CSV"
echo "\"name\",\"device_name\",\"serial\",\"os_version\",\"latest_major_os\",\"product_name\"" > "$NEEDS_UPDATE_CSV"

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
            raw=$(curl -sS -u "${API_KEY}:" -w "\n%{http_code}" "$url" || true)
            http_code=$(printf '%s' "$raw" | tail -1)
            body=$(printf '%s' "$raw" | sed '$d')  # drop status line

            if [[ "$http_code" == "200" ]] && echo "$body" | jq -e '.data' &>/dev/null; then
                resp_body="$body"
                break
            fi

            echo "Fetch attempt $((attempt+1)) failed (HTTP $http_code)."
            printf '%s\n' "$body" | head -c 800

            attempt=$((attempt + 1))
            if (( attempt >= max_attempts )); then
                echo "ERROR: giving up after $attempt attempts on URL: $url" >&2
                echo "Last full response:" >&2
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

    # dedupe and cache
    all_devices_deduped=$(echo "$all_devices" | jq 'unique_by(.id)')
    echo "{\"data\":$all_devices_deduped}" > "$CACHED_DEVICES_JSON"
else
    echo "Loading devices from cache."
    all_devices_deduped=$(jq '.data' "$CACHED_DEVICES_JSON")
fi

response="{\"data\":$all_devices_deduped}"
echo "Total unique devices in use: $(echo "$all_devices_deduped" | jq 'length')"
echo "$all_devices_deduped" | jq . > "$ALL_DEVICES_JSON"
open "$ALL_DEVICES_JSON"

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
    curl -s "https://sofafeed.macadmins.io/v1/macos_data_feed.json" -o "$SOFA_JSON"
else
    echo "Loaded SOFA feed from cache."
fi

# ---------- 3. Get Latest macOS Version by Major ----------
declare -A latest_os_by_major

for i in {0..10}; do
    os_version=$(/usr/bin/plutil -extract "OSVersions.$i.OSVersion" raw "$SOFA_JSON" 2>/dev/null || true)
    product_version=$(/usr/bin/plutil -extract "OSVersions.$i.Latest.ProductVersion" raw "$SOFA_JSON" 2>/dev/null || true)

    if [[ -n "$os_version" && -n "$product_version" ]]; then
        major=$(echo "$product_version" | cut -d'.' -f1)
        latest_os_by_major["$major"]="$product_version"
    fi
done

# ---------- 4. PROCESS DEVICES ----------
echo "$response" | jq -c '.data[]' | while read -r device; do
    name=$(echo "$device" | jq -r '.attributes.name // empty')
    device_name=$(echo "$device" | jq -r '.attributes.device_name // empty')
    serial=$(echo "$device" | jq -r '.attributes.serial_number // empty')
    os_version=$(echo "$device" | jq -r '.attributes.os_version // empty')
    product_name=$(echo "$device" | jq -r '.attributes.product_name // empty')

    os_major=$(echo "$os_version" | cut -d'.' -f1)
    latest_major_os="${latest_os_by_major[$os_major]:-}"

    needs_update="no"
    if [[ -n "$latest_major_os" && -n "$os_version" && "$latest_major_os" != "$os_version" ]]; then
        needs_update="yes"
    fi

    latest_compatible_os=$(/usr/bin/plutil -extract "Models.$product_name.SupportedOS.0" raw -expect string "$SOFA_JSON" 2>/dev/null || true)
    latest_compatible_os_version=""
    if [[ -n "$latest_compatible_os" ]]; then
        for i in {0..10}; do
            os_ver=$(/usr/bin/plutil -extract "OSVersions.$i.OSVersion" raw "$SOFA_JSON" 2>/dev/null || true)
            if [[ "$os_ver" == "$latest_compatible_os" ]]; then
                latest_compatible_os_version=$(/usr/bin/plutil -extract "OSVersions.$i.Latest.ProductVersion" raw "$SOFA_JSON" 2>/dev/null || true)
                break
            fi
        done
    fi

    echo "\"$name\",\"$device_name\",\"$serial\",\"$os_version\",\"$latest_major_os\",\"$needs_update\",\"$product_name\",\"$latest_compatible_os\",\"$latest_compatible_os_version\"" >> "$FULL_CSV"

    if [[ "$needs_update" == "yes" ]]; then
        echo "\"$name\",\"$device_name\",\"$serial\",\"$os_version\",\"$latest_major_os\",\"$product_name\"" >> "$NEEDS_UPDATE_CSV"
    fi
done

# ---------- 5. Export Supported macOS per Model ----------
echo "product_name,marketing_name,latest_compatible_os,latest_compatible_os_version" > "$SUPPORTED_CSV"
product_names=$(echo "$response" | jq -r '.data[].attributes.product_name' | sort -u | grep -v null || true)

for model in $product_names; do
    latest_compatible_os=$(/usr/bin/plutil -extract "Models.$model.SupportedOS.0" raw -expect string "$SOFA_JSON" 2>/dev/null || true)
    [[ -z "$latest_compatible_os" ]] && continue

    latest_compatible_os_version=""
    for i in {0..10}; do
        os_ver=$(/usr/bin/plutil -extract "OSVersions.$i.OSVersion" raw "$SOFA_JSON" 2>/dev/null || true)
        if [[ "$os_ver" == "$latest_compatible_os" ]]; then
            latest_compatible_os_version=$(/usr/bin/plutil -extract "OSVersions.$i.Latest.ProductVersion" raw "$SOFA_JSON" 2>/dev/null || true)
            break
        fi
    done

    marketing_name=$(/usr/bin/plutil -extract "Models.$model.MarketingName" raw "$SOFA_JSON" 2>/dev/null || true)
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
