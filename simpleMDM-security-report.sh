#!/usr/bin/env bash
set -euo pipefail

# simpleMDM-security-report.sh
# Generates a security report from SimpleMDM devices, flagging:
#   - macOS minor and major versions out of date
#   - Unfixed CVEs (from SOFA SecurityReleases)
#   - XProtect outdated (compared against SOFA feed)
#   - FileVault disabled
#   - SIP disabled
#   - Firewall disabled
# Recommends upgrading to actively supported macOS versions (top 2 majors).
# Sorted by last seen (most recent first).
#
# Usage:
#   ./simpleMDM-security-report.sh [--force]
#   --force : ignore cache and re-fetch from API
#
# Set API_KEY env var or you will be prompted.

# ---------- DEPENDENCY CHECKS ----------
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; exit 1; }
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
SECURITY_CSV="${OUTPUT_DIR}/simplemdm_security_report_${DATE}.csv"
SECURITY_SUMMARY="${OUTPUT_DIR}/simplemdm_security_summary_${DATE}.txt"

# ---------- PRECHECK ----------
if [[ -z "$API_KEY" ]]; then
    echo "ERROR: API_KEY is empty." >&2
    exit 1
fi

# ---------- 1. FETCH / CACHE DEVICES ----------
need_fetch_devices=0
if (( FORCE == 1 )); then
    echo "--force given, will re-fetch devices."
    need_fetch_devices=1
elif [[ ! -f "$CACHED_DEVICES_JSON" ]]; then
    echo "No cached device list found; will fetch."
    need_fetch_devices=1
else
    age=$(( $(date +%s) - $(stat -f %m "$CACHED_DEVICES_JSON") ))
    if (( age >= 86400 )); then
        echo "Cached device list older than a day; will refresh."
        need_fetch_devices=1
    else
        echo "Using cached device list (age ${age}s)."
    fi
fi

if (( need_fetch_devices == 1 )); then
    echo "Fetching devices from SimpleMDM API..."
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

        echo "== Fetching page $page =="
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
            attempt=$((attempt + 1))
            if (( attempt >= max_attempts )); then
                echo "ERROR: giving up after $attempt attempts." >&2
                exit 1
            fi
            sleep "$backoff"
            backoff=$(( backoff * 2 ))
        done

        data_array=$(echo "$resp_body" | jq '.data')
        count=$(echo "$data_array" | jq 'length')
        last_id=$(echo "$data_array" | jq -r '.[-1].id // empty')
        has_more=$(echo "$resp_body" | jq -r '.has_more // "false"')
        echo "Page $page: $count devices (has_more=$has_more)"

        all_devices=$(jq -s '.[0] + .[1]' <(echo "$all_devices") <(echo "$data_array"))

        if [[ "$has_more" != "true" || -z "$last_id" ]]; then
            break
        fi

        starting_after="$last_id"
        ((page++))
    done

    all_devices_deduped=$(echo "$all_devices" | jq 'unique_by(.id)')
    echo "{\"data\":$all_devices_deduped}" > "$CACHED_DEVICES_JSON"
else
    all_devices_deduped=$(jq '.data' "$CACHED_DEVICES_JSON")
fi

total_devices=$(echo "$all_devices_deduped" | jq 'length')
echo "Total devices: $total_devices"

# ---------- 2. FETCH / CACHE SOFA FEED ----------
need_fetch_sofa=0
if (( FORCE == 1 )); then
    need_fetch_sofa=1
elif [[ ! -f "$SOFA_JSON" ]]; then
    need_fetch_sofa=1
else
    age=$(( $(date +%s) - $(stat -f %m "$SOFA_JSON") ))
    if (( age >= 86400 )); then
        need_fetch_sofa=1
    fi
fi

if (( need_fetch_sofa == 1 )); then
    echo "Downloading SOFA feed..."
    curl -s "https://sofafeed.macadmins.io/v1/macos_data_feed.json" -A "$user_agent" -o "$SOFA_JSON"
else
    echo "Using cached SOFA feed."
fi

# ---------- 3. BUILD LATEST OS LOOKUP, CVE INDEX & XPROTECT ----------
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

# Get latest XProtect versions from SOFA
SOFA_XP_CONFIG=$(jq -r '.XProtectPlistConfigData."com.apple.XProtect" // empty' "$SOFA_JSON")
SOFA_XP_FRAMEWORK=$(jq -r '.XProtectPayloads."com.apple.XProtectFramework.XProtect" // empty' "$SOFA_JSON")
echo "SOFA XProtect Config Data: ${SOFA_XP_CONFIG:-unknown}"
echo "SOFA XProtect Framework: ${SOFA_XP_FRAMEWORK:-unknown}"

# Build CVE index
CVE_INDEX_DIR=$(mktemp -d)
for (( i=0; i<os_versions_count; i++ )); do
    major=$(jq -r ".OSVersions[$i].Latest.ProductVersion // empty" "$SOFA_JSON" | cut -d'.' -f1)
    [[ -z "$major" ]] && continue
    jq -r ".OSVersions[$i].SecurityReleases // [] | .[] | \"\(.ProductVersion)\t\(.CVEs // {} | keys | join(\",\"))\"" "$SOFA_JSON" > "${CVE_INDEX_DIR}/releases_${major}.tsv" 2>/dev/null || true
done

# Function to count unfixed CVEs for a device
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

# Build upgrade recommendation for a device
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

    [[ -n "$recommendations" ]] && echo "Upgrade to $recommendations"
}

# Fetch XProtect custom attribute for a device
# Returns: "current", "outdated:device_ver:latest_ver", "invalid", or "none"
get_xprotect_status() {
    local device_id="$1"

    local resp
    resp=$(curl -sS -u "${API_KEY}:" -A "$user_agent" \
        "https://a.simplemdm.com/api/v1/devices/${device_id}/custom_attribute_values" 2>/dev/null || true)

    [[ -z "$resp" ]] && echo "none" && return

    # Find any attribute with "xprotect" in the id (case-insensitive)
    local xp_values
    xp_values=$(echo "$resp" | jq -r '.data[]? | select(.id | ascii_downcase | contains("xprotect")) | "\(.id)\t\(.attributes.value // "")"' 2>/dev/null || true)

    [[ -z "$xp_values" ]] && echo "none" && return

    while IFS=$'\t' read -r attr_id attr_value; do
        # Clean value: strip "(Latest: ...)" suffix
        local clean_val
        clean_val=$(echo "$attr_value" | sed 's/ *(.*//;s/^ *//;s/ *$//')

        [[ -z "$clean_val" ]] && continue

        # Check if numeric
        if ! [[ "$clean_val" =~ ^[0-9]+$ ]]; then
            echo "invalid"
            return
        fi

        # Determine which SOFA value to compare against
        local latest=""
        local lower_id
        lower_id=$(echo "$attr_id" | tr '[:upper:]' '[:lower:]')

        if [[ "$lower_id" == *"framework"* ]]; then
            latest="$SOFA_XP_FRAMEWORK"
        elif [[ "$lower_id" == *"config"* || "$lower_id" == *"plist"* ]]; then
            latest="$SOFA_XP_CONFIG"
        elif [[ "$lower_id" == *"plugin"* ]]; then
            latest=$(jq -r '.XProtectPayloads."com.apple.XprotectFramework.PluginService" // empty' "$SOFA_JSON")
        elif (( clean_val >= 1000 )); then
            latest="$SOFA_XP_CONFIG"
        else
            latest="$SOFA_XP_FRAMEWORK"
        fi

        if [[ -n "$latest" && "$clean_val" != "$latest" ]]; then
            echo "outdated:${clean_val}:${latest}"
            return
        elif [[ -n "$latest" && "$clean_val" == "$latest" ]]; then
            echo "current"
            return
        fi
    done <<< "$xp_values"

    echo "current"
}

# ---------- 4. GENERATE SECURITY REPORT ----------
echo '"name","device_name","serial","os_version","latest_minor_os","os_outdated","unfixed_cves","xprotect_status","filevault","sip","firewall","issues","product_name","last_seen_at"' > "$SECURITY_CSV"

TMPFILE=$(mktemp)

device_index=0
echo "$all_devices_deduped" | jq -c '.[]' | while read -r device; do
    device_index=$((device_index + 1))
    device_id=$(echo "$device" | jq -r '.id')
    name=$(echo "$device" | jq -r '.attributes.name // empty')
    device_name=$(echo "$device" | jq -r '.attributes.device_name // empty')
    serial=$(echo "$device" | jq -r '.attributes.serial_number // empty')
    os_version=$(echo "$device" | jq -r '.attributes.os_version // empty')
    product_name=$(echo "$device" | jq -r '.attributes.product_name // empty')
    filevault=$(echo "$device" | jq -r '.attributes.filevault_enabled // empty')
    sip=$(echo "$device" | jq -r '.attributes.system_integrity_protection_enabled // empty')
    firewall=$(echo "$device" | jq -r '.attributes.firewall.enabled // empty')
    last_seen_at=$(echo "$device" | jq -r '.attributes.last_seen_at // empty')

    echo "  Checking device $device_index/$total_devices: $name"

    last_seen_fmt=""
    if [[ -n "$last_seen_at" ]]; then
        last_seen_fmt=$(date -j -f "%Y-%m-%dT%H:%M:%S.%NZ" "$last_seen_at" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$last_seen_at")
    fi

    os_major=$(echo "$os_version" | cut -d'.' -f1)
    latest_minor="${latest_os_by_major[$os_major]:-}"
    os_outdated="no"
    if [[ -n "$latest_minor" && -n "$os_version" && "$latest_minor" != "$os_version" ]]; then
        os_outdated="yes"
    fi

    # Count unfixed CVEs
    unfixed_cves=0
    if [[ -n "$os_version" && -n "$os_major" ]]; then
        unfixed_cves=$(count_unfixed_cves "$os_version" "$os_major")
    fi

    # Check XProtect
    xp_status=$(get_xprotect_status "$device_id")
    xp_csv="current"
    case "$xp_status" in
        current) xp_csv="current" ;;
        outdated:*) xp_csv="outdated" ;;
        invalid) xp_csv="invalid" ;;
        none) xp_csv="n/a" ;;
    esac

    # Collect issues
    issues=""
    has_issue=0

    if [[ "$os_outdated" == "yes" ]]; then
        upgrade_rec=$(get_upgrade_recommendation "$os_major" "$product_name")
        if [[ -n "$upgrade_rec" ]]; then
            issues="$upgrade_rec"
        elif [[ -n "$latest_minor" ]]; then
            issues="Update to $latest_minor"
        else
            issues="OS outdated"
        fi
        has_issue=1
    fi

    if (( unfixed_cves > 0 )); then
        [[ -n "$issues" ]] && issues="$issues; "
        issues="${issues}${unfixed_cves} unfixed CVEs"
        has_issue=1
    fi

    if [[ "$xp_status" == outdated:* ]]; then
        local_ver=$(echo "$xp_status" | cut -d: -f2)
        latest_ver=$(echo "$xp_status" | cut -d: -f3)
        [[ -n "$issues" ]] && issues="$issues; "
        issues="${issues}XProtect outdated ($local_ver → $latest_ver)"
        has_issue=1
    elif [[ "$xp_status" == "invalid" ]]; then
        [[ -n "$issues" ]] && issues="$issues; "
        issues="${issues}XProtect invalid value"
        has_issue=1
    fi

    if [[ "$filevault" == "false" ]]; then
        [[ -n "$issues" ]] && issues="$issues; "
        issues="${issues}FileVault disabled"
        has_issue=1
    fi

    if [[ "$sip" == "false" ]]; then
        [[ -n "$issues" ]] && issues="$issues; "
        issues="${issues}SIP disabled"
        has_issue=1
    fi

    if [[ "$firewall" == "false" ]]; then
        [[ -n "$issues" ]] && issues="$issues; "
        issues="${issues}Firewall disabled"
        has_issue=1
    fi

    if (( has_issue == 1 )); then
        fv_status="enabled"
        [[ "$filevault" == "false" ]] && fv_status="disabled"
        [[ -z "$filevault" ]] && fv_status="unknown"

        sip_status="enabled"
        [[ "$sip" == "false" ]] && sip_status="disabled"
        [[ -z "$sip" ]] && sip_status="unknown"

        fw_status="enabled"
        [[ "$firewall" == "false" ]] && fw_status="disabled"
        [[ -z "$firewall" ]] && fw_status="unknown"

        sort_key="${last_seen_at:-0000}"
        echo "${sort_key}|\"$name\",\"$device_name\",\"$serial\",\"$os_version\",\"$latest_minor\",\"$os_outdated\",\"$unfixed_cves\",\"$xp_csv\",\"$fv_status\",\"$sip_status\",\"$fw_status\",\"$issues\",\"$product_name\",\"$last_seen_fmt\"" >> "$TMPFILE"
    fi
done

sort -t'|' -k1 -r "$TMPFILE" | cut -d'|' -f2- >> "$SECURITY_CSV"
rm -f "$TMPFILE"
rm -rf "$CVE_INDEX_DIR"

# ---------- 5. GENERATE SUMMARY ----------
flagged=$(( $(wc -l < "$SECURITY_CSV" | tr -d ' ') - 1 ))

count_os_outdated=$(awk -F',' '$6 ~ /yes/' "$SECURITY_CSV" | wc -l | tr -d ' ')
count_xp_outdated=$(awk -F',' '$8 ~ /outdated/' "$SECURITY_CSV" | wc -l | tr -d ' ')
count_xp_invalid=$(awk -F',' '$8 ~ /invalid/' "$SECURITY_CSV" | wc -l | tr -d ' ')
count_no_filevault=$(awk -F',' '$9 ~ /disabled/' "$SECURITY_CSV" | wc -l | tr -d ' ')
count_no_sip=$(awk -F',' '$10 ~ /disabled/' "$SECURITY_CSV" | wc -l | tr -d ' ')
count_no_firewall=$(awk -F',' '$11 ~ /disabled/' "$SECURITY_CSV" | wc -l | tr -d ' ')
count_with_unfixed_cves=$(awk -F',' '$7 > 0' "$SECURITY_CSV" | wc -l | tr -d ' ')

cat <<EOF > "$SECURITY_SUMMARY"
SimpleMDM Security Report
Generated: $(date +"%Y-%m-%d %H:%M:%S")
================================================

SOFA XProtect Latest:
  Config Data:            ${SOFA_XP_CONFIG:-unknown}
  Framework:              ${SOFA_XP_FRAMEWORK:-unknown}

Total devices:            $total_devices
Devices with issues:      $flagged

Issue Breakdown:
  OS outdated:            $count_os_outdated
  Unfixed CVEs:           $count_with_unfixed_cves
  XProtect outdated:      $count_xp_outdated
  XProtect invalid:       $count_xp_invalid
  FileVault disabled:     $count_no_filevault
  SIP disabled:           $count_no_sip
  Firewall disabled:      $count_no_firewall

Compliance Rate:
EOF

if (( total_devices > 0 )); then
    clean=$(( total_devices - flagged ))
    pct=$(( clean * 100 / total_devices ))
    echo "  $pct% of devices have no security issues" >> "$SECURITY_SUMMARY"
else
    echo "  No devices to evaluate" >> "$SECURITY_SUMMARY"
fi

cat <<EOF >> "$SECURITY_SUMMARY"

Files:
  Security report CSV:    $SECURITY_CSV
  This summary:           $SECURITY_SUMMARY
EOF

# ---------- 6. OUTPUT ----------
echo ""
cat "$SECURITY_SUMMARY"
echo ""
echo "✅ Security Report Complete"
echo "  → Report CSV:  $SECURITY_CSV"
echo "  → Summary:     $SECURITY_SUMMARY"

open "$SECURITY_CSV"
open "$SECURITY_SUMMARY"
