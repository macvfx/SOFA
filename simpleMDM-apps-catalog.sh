#!/usr/bin/env bash
set -euo pipefail

# simpleMDM-apps-catalog.sh
# Fetches all apps from SimpleMDM with pagination, categorizes by
# installation channel (MDM vs Munki vs both), and exports to CSV.
#
# Usage:
#   ./simpleMDM-apps-catalog.sh [--force]
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

user_agent="SimpleMDMExporter/2.8"

CACHED_APPS_JSON="${CACHE_DIR}/simplemdm_all_apps_cached.json"
ALL_APPS_CSV="${OUTPUT_DIR}/simplemdm_apps_catalog_${DATE}.csv"
MDM_APPS_CSV="${OUTPUT_DIR}/simplemdm_apps_mdm_${DATE}.csv"
MUNKI_APPS_CSV="${OUTPUT_DIR}/simplemdm_apps_munki_${DATE}.csv"
ALL_APPS_JSON="${OUTPUT_DIR}/simplemdm_all_apps_${DATE}.json"

# ---------- CSV HEADERS ----------
HEADER='"name","app_type","version","bundle_identifier","installation_channels","platform_support"'
echo "$HEADER" > "$ALL_APPS_CSV"
echo "$HEADER" > "$MDM_APPS_CSV"
echo "$HEADER" > "$MUNKI_APPS_CSV"

# ---------- PRECHECK ----------
if [[ -z "$API_KEY" ]]; then
    echo "ERROR: API_KEY is empty." >&2
    exit 1
fi

# ---------- 1. FETCH / CACHE APPS ----------
need_fetch=0
if (( FORCE == 1 )); then
    echo "--force given, will re-fetch apps."
    need_fetch=1
elif [[ ! -f "$CACHED_APPS_JSON" ]]; then
    echo "No cached apps found; will fetch."
    need_fetch=1
else
    age=$(( $(date +%s) - $(stat -f %m "$CACHED_APPS_JSON") ))
    if (( age >= 86400 )); then
        echo "Cached apps older than a day; will refresh."
        need_fetch=1
    else
        echo "Using cached apps (age ${age}s)."
    fi
fi

if (( need_fetch == 1 )); then
    echo "Fetching apps from SimpleMDM API..."
    LIMIT=100
    starting_after=""
    all_apps="[]"
    page=1

    while :; do
        if [[ -z "$starting_after" ]]; then
            url="https://a.simplemdm.com/api/v1/apps?limit=${LIMIT}"
        else
            url="https://a.simplemdm.com/api/v1/apps?limit=${LIMIT}&starting_after=${starting_after}"
        fi

        echo "== Fetching page $page =="
        raw=$(curl -sS -u "${API_KEY}:" -A "$user_agent" -w "\n%{http_code}" "$url" || true)
        http_code=$(printf '%s' "$raw" | tail -1)
        body=$(printf '%s' "$raw" | sed '$d')

        if [[ "$http_code" != "200" ]]; then
            echo "ERROR: HTTP $http_code fetching apps." >&2
            if [[ "$http_code" == "403" ]]; then
                echo "Your API key may not have permission for the /apps endpoint." >&2
                echo "Apps require an API key with app management access (not read-only)." >&2
            fi
            printf '%s\n' "$body" | head -c 500 >&2
            exit 1
        fi

        data_array=$(echo "$body" | jq '.data')
        count=$(echo "$data_array" | jq 'length')
        last_id=$(echo "$data_array" | jq -r '.[-1].id // empty')
        has_more=$(echo "$body" | jq -r '.has_more // "false"')
        echo "Page $page: $count apps (has_more=$has_more)"

        all_apps=$(jq -s '.[0] + .[1]' <(echo "$all_apps") <(echo "$data_array"))

        if [[ "$has_more" != "true" || -z "$last_id" ]]; then
            break
        fi

        starting_after="$last_id"
        ((page++))
    done

    all_apps_deduped=$(echo "$all_apps" | jq 'unique_by(.id)')
    echo "{\"data\":$all_apps_deduped}" > "$CACHED_APPS_JSON"
else
    all_apps_deduped=$(jq '.data' "$CACHED_APPS_JSON")
fi

total=$(echo "$all_apps_deduped" | jq 'length')
echo "Total apps: $total"

# Save full JSON
echo "$all_apps_deduped" | jq . > "$ALL_APPS_JSON"

# ---------- 2. PROCESS APPS ----------
mdm_count=0
munki_count=0
both_count=0

echo "$all_apps_deduped" | jq -c '.[]' | while read -r app; do
    name=$(echo "$app" | jq -r '.attributes.name // empty')
    app_type=$(echo "$app" | jq -r '.attributes.app_type // empty')
    version=$(echo "$app" | jq -r '.attributes.version // empty')
    bundle_id=$(echo "$app" | jq -r '.attributes.bundle_identifier // empty')
    channels=$(echo "$app" | jq -r '.attributes.installation_channels // [] | join(", ")')
    platform=$(echo "$app" | jq -r '.attributes.platform_support // empty')

    row="\"$name\",\"$app_type\",\"$version\",\"$bundle_id\",\"$channels\",\"$platform\""

    # All apps
    echo "$row" >> "$ALL_APPS_CSV"

    # Categorize
    is_mdm=$(echo "$app" | jq -r '.attributes.installation_channels // [] | contains(["standard"])')
    is_munki=$(echo "$app" | jq -r '.attributes.installation_channels // [] | contains(["munki"])')

    if [[ "$is_mdm" == "true" ]]; then
        echo "$row" >> "$MDM_APPS_CSV"
    fi
    if [[ "$is_munki" == "true" ]]; then
        echo "$row" >> "$MUNKI_APPS_CSV"
    fi
done

# ---------- 3. SUMMARY ----------
all_count=$(wc -l < "$ALL_APPS_CSV" | tr -d ' ')
mdm_count=$(wc -l < "$MDM_APPS_CSV" | tr -d ' ')
munki_count=$(wc -l < "$MUNKI_APPS_CSV" | tr -d ' ')
# Subtract 1 for header
all_count=$((all_count - 1))
mdm_count=$((mdm_count - 1))
munki_count=$((munki_count - 1))

echo ""
echo "✅ Apps Catalog Export Complete"
echo "  Total apps:  $all_count"
echo "  MDM apps:    $mdm_count"
echo "  Munki apps:  $munki_count"
echo ""
echo "  → All apps CSV:   $ALL_APPS_CSV"
echo "  → MDM apps CSV:   $MDM_APPS_CSV"
echo "  → Munki apps CSV: $MUNKI_APPS_CSV"
echo "  → All apps JSON:  $ALL_APPS_JSON"

open "$ALL_APPS_CSV"
