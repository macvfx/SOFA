#!/bin/bash
# SimpleMDM-IntelInventory.sh
# One-line Intel-only app inventory for a SimpleMDM custom attribute.

set -u

make_temp_file() {
    local temp_root="${TMPDIR:-/tmp}"
    if [ ! -d "$temp_root" ] || [ ! -w "$temp_root" ]; then
        temp_root="/tmp"
    fi
    mktemp "$temp_root/simplemdm_intel_inventory.XXXXXX"
}

results="$(make_temp_file)"
trap 'rm -f "$results"' EXIT

app_search_paths=("/Applications" "/Applications/Utilities")

display_item_for_app() {
    local app="$1"
    if [ "${app#/Applications/}" != "$app" ]; then
        local relative_path="${app#/Applications/}"
        case "$relative_path" in
            */*)
                local top_level="${relative_path%%/*}"
                local rest_path="${relative_path#*/}"
                if [ "$top_level" = "Utilities" ] && [ "$rest_path" = "$(basename "$app")" ]; then
                    basename "$app" .app
                else
                    printf '%s\n' "$top_level"
                fi
                ;;
            *) basename "$app" .app ;;
        esac
        return
    fi
    basename "$(dirname "$app")"
}

is_intel_only_macho() {
    local target="$1"
    local info
    info="$(file "$target" 2>/dev/null)"
    echo "$info" | grep -q "Mach-O" || return 1
    echo "$info" | grep -q "x86_64" || return 1
    echo "$info" | grep -q "arm64" && return 1
    return 0
}

app_executable_path() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    [ -f "$plist" ] || return 1
    local executable_name
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null)"
    [ -n "$executable_name" ] || return 1
    local executable_path="$app/Contents/MacOS/$executable_name"
    [ -f "$executable_path" ] || return 1
    printf '%s\n' "$executable_path"
}

for directory in "${app_search_paths[@]}"; do
    [ -d "$directory" ] || continue
    find "$directory" -name "*.app" -type d -prune -print0 2>/dev/null |
        while IFS= read -r -d '' app; do
            executable_path="$(app_executable_path "$app" || true)"
            [ -n "$executable_path" ] || continue
            if is_intel_only_macho "$executable_path"; then
                display_item_for_app "$app" >> "$results"
            fi
        done
done

count="$(sort -u "$results" | wc -l | tr -d ' ')"
app_names="$(sort -u "$results" | paste -sd ',' -)"
scanned_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
architecture="$(uname -m)"

if [ -z "$app_names" ]; then
    app_names="none"
fi

printf 'v=2;count=%s;apps=%s;scanned_at=%s;arch=%s\n' \
    "$count" "$app_names" "$scanned_at" "$architecture"
