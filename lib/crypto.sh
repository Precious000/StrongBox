#!/bin/bash
# Envelope encryption for StrongBox
# Layer 1: plaintext encrypted with DEK (random per secret, AES-256-GCM)
# Layer 2: DEK encrypted with KEK (master key, lives only in memory)
# KEK is NEVER written to disk or logged under any circumstance.

# In-memory KEK - shell variable, never written to disk
STRONGBOX_KEK=""

crypto_set_kek() {
STRONGBOX_KEK="$1"
}

crypto_clear_kek() {
STRONGBOX_KEK=""
}

crypto_is_unsealed() {
[[ -n "$STRONGBOX_KEK" ]]
}

crypto_generate_key() {
# 256-bit key from CSPRNG via /dev/urandom through openssl
openssl rand -hex 32
}

crypto_generate_nonce() {
# 96-bit (12-byte) random nonce - fresh per encryption operation
# Random strategy chosen over counter to avoid synchronization
# requirements in a multi-node cluster
openssl rand -hex 12
}

crypto_aes_gcm_encrypt() {
local key_hex="$1"
local nonce_hex="$2"
local plaintext="$3"
printf '%s' "$plaintext" | openssl enc -aes-256-gcm \
-K "$key_hex" \
-iv "$nonce_hex" \
-nosalt \
-a 2>/dev/null | tr -d '\n'
}

crypto_aes_gcm_decrypt() {
local key_hex="$1"
local nonce_hex="$2"
local ciphertext_b64="$3"
printf '%s' "$ciphertext_b64" | openssl enc -aes-256-gcm \
-d \
-K "$key_hex" \
-iv "$nonce_hex" \
-nosalt \
-a 2>/dev/null
}

crypto_wrap_dek() {
# Encrypt a DEK with the in-memory KEK
# Usage: crypto_wrap_dek DEK_HEX
# Returns: JSON {wrapped_dek, nonce}
local dek_hex="$1"

if [[ -z "$STRONGBOX_KEK" ]]; then
echo '{"error":"vault is sealed - no KEK in memory"}' >&2
return 1
fi

local nonce
nonce=$(crypto_generate_nonce)
local wrapped
wrapped=$(crypto_aes_gcm_encrypt "$STRONGBOX_KEK" "$nonce" "$dek_hex")

echo "{\"wrapped_dek\":\"${wrapped}\",\"nonce\":\"${nonce}\"}"
}

crypto_unwrap_dek() {
# Decrypt a wrapped DEK using the in-memory KEK
# Usage: crypto_unwrap_dek WRAPPED_DEK NONCE
# Returns: DEK hex on stdout
local wrapped_dek="$1"
local nonce="$2"

if [[ -z "$STRONGBOX_KEK" ]]; then
echo "vault is sealed" >&2
return 1
fi

crypto_aes_gcm_decrypt "$STRONGBOX_KEK" "$nonce" "$wrapped_dek"
}

crypto_encrypt_secret() {
# Full envelope encryption
# Usage: crypto_encrypt_secret PLAINTEXT
# Returns: JSON {ciphertext, nonce, wrapped_dek, dek_nonce}
local plaintext="$1"

# Generate fresh DEK for this secret only
local dek
dek=$(crypto_generate_key)
local nonce
nonce=$(crypto_generate_nonce)

# Encrypt secret data with DEK
local ciphertext
ciphertext=$(crypto_aes_gcm_encrypt "$dek" "$nonce" "$plaintext")

# Wrap DEK with KEK
local wrap_result
wrap_result=$(crypto_wrap_dek "$dek")
if [[ $? -ne 0 ]]; then
dek=""
return 1
fi

local wrapped_dek dek_nonce
wrapped_dek=$(echo "$wrap_result" | python3 -c \
"import sys,json; print(json.load(sys.stdin)['wrapped_dek'])")
dek_nonce=$(echo "$wrap_result" | python3 -c \
"import sys,json; print(json.load(sys.stdin)['nonce'])")

# Zero DEK from local variable immediately after wrapping
dek=""

echo "{\"ciphertext\":\"${ciphertext}\",\"nonce\":\"${nonce}\",\"wrapped_dek\":\"${wrapped_dek}\",\"dek_nonce\":\"${dek_nonce}\"}"
}

crypto_decrypt_secret() {
# Full envelope decryption
# Usage: crypto_decrypt_secret CIPHERTEXT NONCE WRAPPED_DEK DEK_NONCE
# Returns: plaintext on stdout
local ciphertext="$1"
local nonce="$2"
local wrapped_dek="$3"
local dek_nonce="$4"

# Unwrap DEK using KEK
local dek
dek=$(crypto_unwrap_dek "$wrapped_dek" "$dek_nonce")
if [[ $? -ne 0 ]]; then
return 1
fi

# Decrypt with DEK
local plaintext
plaintext=$(crypto_aes_gcm_decrypt "$dek" "$nonce" "$ciphertext")

# Zero DEK immediately after use
dek=""

printf '%s' "$plaintext"
}

crypto_hmac_sha256() {
# Usage: crypto_hmac_sha256 KEY_HEX DATA
local key_hex="$1"
local data="$2"
printf '%s' "$data" | openssl dgst -sha256 -mac HMAC \
-macopt "hexkey:${key_hex}" | awk '{print $2}'
}

crypto_hash_password() {
# Argon2id hash for passwords - never store plaintext
local password="$1"
local salt
salt=$(openssl rand -hex 8)
printf '%s' "$password" | argon2 "$salt" -id -t 3 -m 16 -p 2 -e
}
