
#!/bin/bash

# Auth: tokens, policies, login, revocation

# Token revocation is synchronous - no cache, no grace period.

# A revoked token fails on the very next request.



TOKEN_DIR="${TOKEN_DIR:-/data/tokens}"

POLICY_DIR="${POLICY_DIR:-/data/policies}"

USER_DIR="${USER_DIR:-/data/users}"



auth_init() {

mkdir -p "$TOKEN_DIR" "$POLICY_DIR" "$USER_DIR"

}



auth_generate_token() {

# Opaque, >=32 bytes, from CSPRNG. Not a JWT.

openssl rand -hex 40

}



auth_create_token() {

local policies="$1"

local ttl="${2:-3600}"



local token token_id expires_at created_at

token=$(auth_generate_token)

token_id=$(openssl rand -hex 8)

created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

expires_at=$(python3 -c "

from datetime import datetime, timedelta

print((datetime.utcnow()+timedelta(seconds=$ttl)).strftime('%Y-%m-%dT%H:%M:%SZ'))

")



local token_hash

token_hash=$(printf '%s' "$token" | openssl dgst -sha256 | awk '{print $2}')



python3 -c "

import json

print(json.dumps({

'token_id': '$token_id',

'token_hash': '$token_hash',

'policies': '$policies'.split(','),

'created_at': '$created_at',

'expires_at': '$expires_at',

'revoked': False

}))

" > "$TOKEN_DIR/${token_id}.json"



# Hash index for O(1) lookup on incoming requests

printf '%s' "$token_id" > "$TOKEN_DIR/hash_${token_hash}"



echo "{\"token\":\"$token\",\"token_id\":\"$token_id\",\"policies\":\"$policies\",\"expires_at\":\"$expires_at\"}"

}



auth_validate_token() {

# Called on every request. No caching. Revocation is instant.

local raw_token="$1"



local token_hash

token_hash=$(printf '%s' "$raw_token" | openssl dgst -sha256 | awk '{print $2}')



local index_file="$TOKEN_DIR/hash_${token_hash}"

[[ ! -f "$index_file" ]] && return 1



local token_id

token_id=$(cat "$index_file")

local meta_file="$TOKEN_DIR/${token_id}.json"

[[ ! -f "$meta_file" ]] && return 1



local revoked

revoked=$(python3 -c "import json; print(json.load(open('$meta_file'))['revoked'])")

[[ "$revoked" == "True" ]] && return 1



local expires_at now

expires_at=$(python3 -c "import json; print(json.load(open('$meta_file'))['expires_at'])")

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

[[ "$now" > "$expires_at" ]] && return 1



cat "$meta_file"

return 0

}



auth_revoke_token() {

local raw_token="$1"



local token_hash

token_hash=$(printf '%s' "$raw_token" | openssl dgst -sha256 | awk '{print $2}')

local index_file="$TOKEN_DIR/hash_${token_hash}"

[[ ! -f "$index_file" ]] && return 1



local token_id

token_id=$(cat "$index_file")

local meta_file="$TOKEN_DIR/${token_id}.json"



python3 -c "

import json

with open('$meta_file') as f:

d = json.load(f)

d['revoked'] = True

d['revoked_at'] = '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'

with open('$meta_file', 'w') as f:

json.dump(d, f)

"

}



auth_check_policy() {

local token_id="$1"

local capability="$2"

local path="$3"



local meta_file="$TOKEN_DIR/${token_id}.json"

[[ ! -f "$meta_file" ]] && return 1



python3 -c "

import json

with open('$meta_file') as f:

meta = json.load(f)

policies = meta.get('policies', [])

import os

policy_dir = '$POLICY_DIR'

path = '$path'

capability = '$capability'

for policy_name in policies:

pfile = os.path.join(policy_dir, policy_name + '.json')

if not os.path.exists(pfile):

continue

with open(pfile) as f:

policy = json.load(f)

for rule in policy.get('rules', []):

prefix = rule.get('path', '')

if prefix.endswith('*'):

matches = path.startswith(prefix[:-1])

else:

matches = path == prefix

if matches and capability in rule.get('capabilities', []):

print('allow')

exit(0)

exit(1)

" && return 0

return 1

}



auth_create_policy() {

local name="$1"

local rules="$2"

printf '%s' "$rules" > "$POLICY_DIR/${name}.json"

}



auth_get_policy() {

local name="$1"

local pfile="$POLICY_DIR/${name}.json"

[[ -f "$pfile" ]] && cat "$pfile" && return 0

return 1

}



auth_create_user() {

local username="$1"

local password="$2"

local policies="$3"



local salt password_hash

salt=$(openssl rand -hex 8)

password_hash=$(printf '%s' "$password" | argon2 "$salt" -id -t 3 -m 16 -p 2 -e)



python3 -c "

import json

print(json.dumps({

'username': '$username',

'password_hash': '$password_hash',

'salt': '$salt',

'policies': '$policies'.split(',')

}))

" > "$USER_DIR/${username}.json"

}



auth_login() {

local username="$1"

local password="$2"



local user_file="$USER_DIR/${username}.json"

[[ ! -f "$user_file" ]] && return 1



local stored_hash salt

stored_hash=$(python3 -c "import json; print(json.load(open('$user_file'))['password_hash'])")

salt=$(python3 -c "import json; print(json.load(open('$user_file'))['salt'])")



local computed_hash

computed_hash=$(printf '%s' "$password" | argon2 "$salt" -id -t 3 -m 16 -p 2 -e)



if [[ "$computed_hash" == "$stored_hash" ]]; then

local policies

policies=$(python3 -c "import json; print(','.join(json.load(open('$user_file'))['policies']))")

auth_create_token "$policies"

return 0

fi

return 1

}

