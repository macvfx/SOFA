#!/bin/bash
# xprotect-version-check.sh
# Gets the local XProtect version (XProtectPlistConfigData) and optionally
# pushes it to SimpleMDM as a custom attribute named "xprotect_version".
#
# Usage:
#   ./xprotect-version-check.sh              # Print version only
#   ./xprotect-version-check.sh --push       # Print and push to SimpleMDM
#
# For SimpleMDM push, set API_KEY and DEVICE_ID as env vars.
# Typically run via SimpleMDM script on each device.
#
# Custom Attribute Setup:
#   In SimpleMDM, create a custom attribute named "xprotect_version"
#   The app will auto-detect this and compare against the SOFA feed.

# Get local XProtect version (4-digit config data version, e.g., 5347)
LOCAL_VERSION=$(/usr/bin/xprotect check 2>/dev/null | awk -F ':' '{print $6}' | xargs)

if [[ -z "$LOCAL_VERSION" ]]; then
    echo "ERROR: Could not determine local XProtect version" >&2
    exit 1
fi

echo "$LOCAL_VERSION"

# Optionally push to SimpleMDM custom attribute
if [[ "${1:-}" == "--push" ]]; then
    API_KEY="${API_KEY:-}"
    DEVICE_ID="${DEVICE_ID:-}"

    if [[ -z "$API_KEY" || -z "$DEVICE_ID" ]]; then
        echo "ERROR: Set API_KEY and DEVICE_ID env vars for SimpleMDM push" >&2
        exit 1
    fi

    curl -s -X PUT \
        -u "${API_KEY}:" \
        -H "Content-Type: application/json" \
        -d "{\"value\": \"${LOCAL_VERSION}\"}" \
        "https://a.simplemdm.com/api/v1/devices/${DEVICE_ID}/custom_attribute_values/xprotect_version" \
        > /dev/null

    echo "Pushed xprotect_version=$LOCAL_VERSION to SimpleMDM device $DEVICE_ID"
fi
