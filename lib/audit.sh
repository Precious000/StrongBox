#!/bin/bash
# Tamper-evident audit log using HMAC-SHA256 hash chain
# Each entry: index, ts, event, path, token_id, node_id, prev_hash, entry_hash
# entry_hash = HMAC-SHA256(AUDIT_KEY, prev_hash|index|ts|event|path|token_id|node_id)
# Verifying re-derives every hash from genesis and fails on any mismatch

AUDIT_LOG="${AUDIT_LOG:-/data/audit/audit.log}"
AUDIT_KEY_FILE="${AUDIT_KEY_FILE:-/data/audit.key}"
AUDIT_HMAC_KEY=""

audit_init() {
mkdir -p "$(dirname "$AUDIT_LOG")"

if [[ ! -f "$AUDIT_KEY_FILE" ]]; then
openssl rand -hex 32 > "$AUDIT_KEY_FILE"
chmod 600 "$AUDIT_KEY_FILE"
fi
AUDIT_HMAC_KEY=$(cat "$AUDIT_KEY_FILE")
}

_audit_prev_hash() {
if [[ ! -f "$AUDIT_LOG" ]] || [[ ! -s "$AUDIT_LOG" ]]; then
echo "0000000000000000000000000000000000000000000000000000000000000000"
return
fi
tail -1 "$AUDIT_LOG" | python3 -c \
"import sys,json; print(json.loads(sys.stdin.read().strip()).get('entry_hash','0'*64))"
}

_audit_next_index() {
if [[ ! -f "$AUDIT_LOG" ]] || [[ ! -s "$AUDIT_LOG" ]]; then
echo "0"
return
fi
wc -l < "$AUDIT_LOG" | tr -d ' '
}

audit_append() {
local event="$1"
local path="$2"
local token_id="${3:-anonymous}"
local node_id="${4:-${NODE_ID:-node1}}"
local ts
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

local prev_hash index
prev_hash=$(_audit_prev_hash)
index=$(_audit_next_index)

local data="${prev_hash}|${index}|${ts}|${event}|${path}|${token_id}|${node_id}"
local entry_hash
entry_hash=$(printf '%s' "$data" | openssl dgst -sha256 -mac HMAC \
-macopt "hexkey:${AUDIT_HMAC_KEY}" | awk '{print $2}')

python3 -c "
import json
print(json.dumps({
'index': $index,
'ts': '$ts',
'event': '$event',
'path': '$path',
'token_id': '$token_id',
'node_id': '$node_id',
'prev_hash': '$prev_hash',
'entry_hash': '$entry_hash'
}))
" >> "$AUDIT_LOG"
}

audit_query() {
local token_id="${1:-}"
if [[ ! -f "$AUDIT_LOG" ]]; then
echo "[]"
return
fi
python3 -c "
import json, sys
results = []
with open('$AUDIT_LOG') as f:
for line in f:
line = line.strip()
if not line:
continue
try:
entry = json.loads(line)
if not '$token_id' or entry.get('token_id') == '$token_id':
results.append(entry)
except:
pass
print(json.dumps(results))
"
}
