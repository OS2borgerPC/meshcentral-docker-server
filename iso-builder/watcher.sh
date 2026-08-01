#!/usr/bin/env bash
set -euo pipefail

SCAN_ROOT="${SCAN_ROOT:-/data}"
CACHE_DIR="${CACHE_DIR:-/cache}"
INTERVAL="${INTERVAL:-300}"
FCOS_STREAM="${FCOS_STREAM:-stable}"
FCOS_PLATFORM="${FCOS_PLATFORM:-metal}"

log()    { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"; }
now_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

get_cached_iso() {
    ls -1 "$CACHE_DIR"/fedora-coreos-*.iso 2>/dev/null | sort -V | tail -1 || true
}

get_iso_version() {
    basename "$1" | sed 's/fedora-coreos-\([^-]*\)-.*/\1/'
}

ensure_fcos_iso() {
    local iso
    iso=$(get_cached_iso)
    if [[ -z "$iso" ]]; then
        log "No cached FCOS ISO found. Downloading (stream: $FCOS_STREAM, platform: $FCOS_PLATFORM)..."
        coreos-installer download -s "$FCOS_STREAM" -p "$FCOS_PLATFORM" -f iso -C "$CACHE_DIR"
        iso=$(get_cached_iso)
    fi
    echo "$iso"
}

check_fcos_update() {
    local flag="$CACHE_DIR/.last_fcos_check"
    local now
    now=$(date +%s)

    if [[ -f "$flag" ]]; then
        local last
        last=$(cat "$flag")
        if (( now - last < 86400 )); then
            return 0
        fi
    fi

    log "Checking for FCOS update..."
    local before
    before=$(get_cached_iso)

    coreos-installer download -s "$FCOS_STREAM" -p "$FCOS_PLATFORM" -f iso -C "$CACHE_DIR" 2>/dev/null || true
    date +%s > "$flag"

    local after
    after=$(get_cached_iso)

    if [[ "$before" == "$after" ]]; then
        log "FCOS is up to date."
        return 0
    fi

    local new_version
    new_version=$(get_iso_version "$after")
    log "New FCOS version available: $new_version. Removing old ISO."
    [[ -n "$before" ]] && rm -f "$before"

    # Set ready=true for manifests that opt in to automatic FCOS-triggered rebuilds
    while IFS= read -r manifest; do
        local auto
        auto=$(jq -r '.auto_rebuild_on_fcos_update // false' "$manifest" 2>/dev/null) || continue
        if [[ "$auto" != "true" ]]; then
            continue
        fi
        local tmp
        tmp=$(mktemp)
        jq '.ready = true' "$manifest" > "$tmp" && mv "$tmp" "$manifest"
        log "Queued auto-rebuild: $(dirname "$manifest")"
    done < <(find "$SCAN_ROOT" -name "build-status.json" 2>/dev/null)
}

mark_failed() {
    local manifest="$1" source_hash="$2" fcos_version="$3" reason="$4"
    local tmp
    tmp=$(mktemp)
    jq --arg t "$(now_ts)" --arg h "$source_hash" --arg v "$fcos_version" --arg r "$reason" \
        '.status = "failed" | .finished = $t | .source_hash = $h | .fcos_version = $v | .error = $r' \
        "$manifest" > "$tmp" && mv "$tmp" "$manifest"
    log "Build FAILED: $reason"
}

build_iso() {
    local manifest="$1"
    local dir
    dir=$(dirname "$manifest")

    local source_hash
    source_hash=$(sha256sum "$dir/config.bu" | cut -d' ' -f1)

    # Atomically claim the job: flip ready=false and status=processing before doing any work
    local tmp
    tmp=$(mktemp)
    jq --arg t "$(now_ts)" --arg h "$source_hash" \
        '.ready = false | .status = "processing" | .started = $t | .source_hash = $h | del(.finished) | del(.error)' \
        "$manifest" > "$tmp" && mv "$tmp" "$manifest"

    log "Build started: $dir (source hash: $source_hash)"

    # Step 1: Butane → Ignition
    log "Step 1/3: Running butane..."
    if ! butane --pretty --strict "$dir/config.bu" > "$dir/config.ign"; then
        mark_failed "$manifest" "$source_hash" "" "butane failed — see build.log"
        return 1
    fi

    # Step 2: Ensure FCOS ISO is cached
    log "Step 2/3: Checking FCOS ISO cache..."
    local iso
    iso=$(ensure_fcos_iso) || {
        mark_failed "$manifest" "$source_hash" "" "FCOS ISO download failed"
        return 1
    }
    local fcos_version
    fcos_version=$(get_iso_version "$iso")
    log "Using FCOS $fcos_version ($iso)"

    # Step 3: Customize ISO
    local dest_device
    dest_device=$(jq -r '.dest_device // empty' "$manifest")
    rm -f "$dir/custom.iso"
    if [[ -n "$dest_device" ]]; then
        log "Step 3/3: Customizing ISO (dest-device: $dest_device)..."
        if ! coreos-installer iso customize \
                --dest-ignition "$dir/config.ign" \
                --dest-device "$dest_device" \
                --output "$dir/custom.iso" \
                "$iso"; then
            mark_failed "$manifest" "$source_hash" "$fcos_version" "coreos-installer iso customize failed"
            return 1
        fi
    else
        log "Step 3/3: Customizing ISO (no dest-device specified; leaving installer interactive)..."
        if ! coreos-installer iso customize \
                --dest-ignition "$dir/config.ign" \
                --output "$dir/custom.iso" \
                "$iso"; then
            mark_failed "$manifest" "$source_hash" "$fcos_version" "coreos-installer iso customize failed"
            return 1
        fi
    fi

    # Success
    tmp=$(mktemp)
    jq --arg t "$(now_ts)" --arg h "$source_hash" --arg v "$fcos_version" \
        '.status = "done" | .finished = $t | .source_hash = $h | .fcos_version = $v | del(.error)' \
        "$manifest" > "$tmp" && mv "$tmp" "$manifest"

    log "Build done: $dir/custom.iso"
}

# ---------------------------------------------------------------------------

mkdir -p "$CACHE_DIR"
log "ISO builder started. Scanning '$SCAN_ROOT' every ${INTERVAL}s."

while true; do
    check_fcos_update || log "FCOS update check failed (non-fatal)"

    while IFS= read -r manifest; do
        ready=$(jq -r '.ready // false' "$manifest" 2>/dev/null) || continue
        [[ "$ready" != "true" ]] && continue

        status=$(jq -r '.status // "idle"' "$manifest" 2>/dev/null) || continue
        [[ "$status" == "processing" ]] && continue

        dir=$(dirname "$manifest")
        if [[ ! -f "$dir/config.bu" ]]; then
            log "Warning: ready=true but no config.bu found in $dir"
            continue
        fi

        # Run build; tee all output (stdout + stderr) to build.log in the same directory
        build_iso "$manifest" 2>&1 | tee "$dir/build.log" || true

    done < <(find "$SCAN_ROOT" -name "build-status.json" 2>/dev/null)

    sleep "$INTERVAL"
done
