
#!/bin/bash

# Lease management and background reaper

# Lease states: active, expired, revoked, revocation_pending

# revocation_pending: DB unreachable at revocation time - reaper retries with backoff



LEASE_DIR="${LEASE_DIR:-/data/leases}"

DEFAULT_TTL="${DEFAULT_TTL:-3600}"

MAX_TTL="${MAX_TTL:-86400}"

REAPER_INTERVAL="${REAPER_INTERVAL:-30}"



lease_init() {

mkdir -p "$LEASE_DIR"

}



lease_create() {

local path="$1"

local token_id="$2"

local ttl="${3:-$DEFAULT_TTL}"



[[ $ttl -gt $MAX_TTL ]] && ttl=$MAX_TTL



local lease_id expires_at created_at

lease_id=$(openssl rand -hex 16)

created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

expires_at=$(python3 -c "

from datetime import datetime, timedelta

print((datetime.utcnow()+timedelta(seconds=$ttl)).strftime('%Y-%m-%dT%H:%M:%SZ'))

")



python3 -c "

import json

print(json.dumps({

'lease_id': '$lease_id',

'path': '$path',

'token_id': '$token_id',

'state': 'active',

'ttl': $ttl,

'created_at': '$created_at',

'expires_at': '$expires_at',

'renewable': True

}))

" > "$LEASE_DIR/${lease_id}.json"



echo "{\"lease_id\":\"$lease_id\",\"expires_at\":\"$expires_at\",\"ttl\":$ttl}"

}



lease_get() {

local lease_id="$1"

local lfile="$LEASE_DIR/${lease_id}.json"

[[ -f "$lfile" ]] && cat "$lfile" && return 0

return 1

}



lease_renew() {

local lease_id="$1"

local increment="${2:-$DEFAULT_TTL}"

local lfile="$LEASE_DIR/${lease_id}.json"

[[ ! -f "$lfile" ]] && return 1



python3 -c "

import json

from datetime import datetime, timedelta

with open('$lfile') as f:

d = json.load(f)

if d['state'] != 'active':

exit(1)

expires = datetime.strptime(d['expires_at'], '%Y-%m-%dT%H:%M:%SZ')

new_expires = expires + timedelta(seconds=$increment)

created = datetime.strptime(d['created_at'], '%Y-%m-%dT%H:%M:%SZ')

if (new_expires - created).total_seconds() > $MAX_TTL:

print('ERROR: exceeds max TTL')

exit(1)

d['expires_at'] = new_expires.strftime('%Y-%m-%dT%H:%M:%SZ')

with open('$lfile', 'w') as f:

json.dump(d, f)

print(d['expires_at'])

" && return 0

return 1

}



lease_revoke() {

local lease_id="$1"

local lfile="$LEASE_DIR/${lease_id}.json"

[[ ! -f "$lfile" ]] && return 1

python3 -c "

import json

with open('$lfile') as f:

d = json.load(f)

d['state'] = 'revoked'

d['revoked_at'] = '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'

with open('$lfile', 'w') as f:

json.dump(d, f)

"

}



lease_reaper() {

echo "Lease reaper started interval=${REAPER_INTERVAL}s"

while true; do

sleep "$REAPER_INTERVAL"

local now

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")



for lfile in "$LEASE_DIR"/*.json; do

[[ ! -f "$lfile" ]] && continue



local state expires_at path lease_id

state=$(python3 -c "import json; print(json.load(open('$lfile')).get('state',''))" 2>/dev/null)

expires_at=$(python3 -c "import json; print(json.load(open('$lfile')).get('expires_at',''))" 2>/dev/null)

path=$(python3 -c "import json; print(json.load(open('$lfile')).get('path',''))" 2>/dev/null)

lease_id=$(basename "$lfile" .json)



# Expire active leases past their TTL

if [[ "$state" == "active" ]] && [[ "$now" > "$expires_at" ]]; then

python3 -c "

import json

with open('$lfile') as f: d=json.load(f)

d['state']='expired'

with open('$lfile','w') as f: json.dump(d,f)

"

# Trigger DB role revocation for dynamic secrets

if [[ "$path" == dynamic-postgres/* ]]; then

local role

role=$(python3 -c "import json; print(json.load(open('$lfile')).get('pg_role',''))" 2>/dev/null)

[[ -n "$role" ]] && _lease_revoke_pg_role "$role" "$lease_id" "$lfile"

fi

fi



# Retry revocation_pending leases with backoff

if [[ "$state" == "revocation_pending" ]]; then

local role

role=$(python3 -c "import json; print(json.load(open('$lfile')).get('pg_role',''))" 2>/dev/null)

[[ -n "$role" ]] && _lease_revoke_pg_role "$role" "$lease_id" "$lfile"

fi

done

done

}



_lease_revoke_pg_role() {

local role="$1"

local lease_id="$2"

local lfile="$3"

source "$(dirname "${BASH_SOURCE[0]}")/dynamic.sh"



if dynamic_revoke_role "$role"; then

python3 -c "

import json

with open('$lfile') as f: d=json.load(f)

d['state']='revoked'

d['revoked_at']='$(date -u +"%Y-%m-%dT%H:%M:%SZ")'

with open('$lfile','w') as f: json.dump(d,f)

"

echo "Revoked pg role $role lease $lease_id"

else

# DB unreachable - mark pending, reaper will retry

python3 -c "

import json

with open('$lfile') as f: d=json.load(f)

d['state']='revocation_pending'

d['pg_role']='$role'

d['last_retry']='$(date -u +"%Y-%m-%dT%H:%M:%SZ")'

with open('$lfile','w') as f: json.dump(d,f)

"

echo "WARNING: pg role $role revocation pending - DB unreachable"

fi

}

