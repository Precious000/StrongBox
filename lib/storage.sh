#!/bin/bash
# Storage interface for StrongBox
#
# Interface contract (implement these five functions to swap backends):
# storage_put PATH VALUE → 0 on success
# storage_get PATH → prints value to stdout, returns 0; returns 1 if not found
# storage_delete PATH → 0 on success, 0 if not found (idempotent)
# storage_list PREFIX → prints matching paths one per line, 0 always
# storage_put_version PATH VALUE → prints new version number to stdout, 0 on success
# storage_get_version PATH [VERSION] → prints value at version N, or latest if omitted; 1 if not found
# storage_latest_version PATH → prints latest version number, 0 always (0 if never written)
#
# Current backend: filesystem under STORAGE_DIR
# To swap backend: reimplement these seven functions. No other file needs to change.

STORAGE_DIR="${STORAGE_DIR:-/data/secrets}"

storage_init() {
mkdir -p "$STORAGE_DIR"
}

_safe_path() {
# Convert a key path like secret/app/db to a safe filename
echo "$1" | tr '/' '_' | tr -cd 'a-zA-Z0-9._-'
}

storage_put() {
local path="$1"
local value="$2"
local safe
safe=$(_safe_path "$path")
mkdir -p "$STORAGE_DIR"
printf '%s' "$value" > "$STORAGE_DIR/${safe}"
return 0
}

storage_get() {
local path="$1"
local safe
safe=$(_safe_path "$path")
if [[ -f "$STORAGE_DIR/${safe}" ]]; then
cat "$STORAGE_DIR/${safe}"
return 0
fi
return 1
}

storage_delete() {
local path="$1"
local safe
safe=$(_safe_path "$path")
rm -f "$STORAGE_DIR/${safe}"
rm -f "$STORAGE_DIR/${safe}".v*
rm -f "$STORAGE_DIR/${safe}".meta
return 0
}

storage_list() {
local prefix="$1"
local safe_prefix
safe_prefix=$(_safe_path "$prefix")
find "$STORAGE_DIR" -maxdepth 1 -name "${safe_prefix}*" ! -name "*.meta" \
! -name "*.v*" -type f 2>/dev/null | \
sed "s|$STORAGE_DIR/||" | \
tr '_' '/'
}

storage_put_version() {
local path="$1"
local value="$2"
local safe
safe=$(_safe_path "$path")
mkdir -p "$STORAGE_DIR"

local version=1
if [[ -f "$STORAGE_DIR/${safe}.meta" ]]; then
version=$(( $(cat "$STORAGE_DIR/${safe}.meta") + 1 ))
fi

# Write versioned copy and update latest atomically
printf '%s' "$value" > "$STORAGE_DIR/${safe}.v${version}"
printf '%s' "$value" > "$STORAGE_DIR/${safe}"
printf '%s' "$version" > "$STORAGE_DIR/${safe}.meta"

echo "$version"
return 0
}

storage_get_version() {
local path="$1"
local version="${2:-latest}"
local safe
safe=$(_safe_path "$path")

if [[ "$version" == "latest" ]] || [[ -z "$version" ]]; then
storage_get "$path"
return $?
fi

if [[ -f "$STORAGE_DIR/${safe}.v${version}" ]]; then
cat "$STORAGE_DIR/${safe}.v${version}"
return 0
fi
return 1
}

storage_latest_version() {
local path="$1"
local safe
safe=$(_safe_path "$path")
if [[ -f "$STORAGE_DIR/${safe}.meta" ]]; then
cat "$STORAGE_DIR/${safe}.meta"
else
echo "0"
fi
}
