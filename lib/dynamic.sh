
#!/bin/bash

# Dynamic PostgreSQL secrets engine

# Mints fresh DB roles on read, revokes them when leases expire



PG_HOST="${PG_HOST:-localhost}"

PG_PORT="${PG_PORT:-5432}"

PG_DB="${PG_DB:-postgres}"

PG_ADMIN="${PG_ADMIN:-postgres}"

PG_PASS="${PG_PASS:-postgrespassword}"



_pg() {

PGPASSWORD="$PG_PASS" psql -h "$PG_HOST" -p "$PG_PORT" \
-U "$PG_ADMIN" -d "$PG_DB" -t -c "$1" 2>/dev/null

}



dynamic_mint_postgres_role() {

local role_prefix="${1:-sb}"

local role_name="${role_prefix}_$(openssl rand -hex 6)"

local password

password=$(openssl rand -hex 16)



if ! _pg "SELECT 1" > /dev/null 2>&1; then

echo '{"error":"database unreachable"}' >&2

return 1

fi



_pg "CREATE ROLE ${role_name} WITH LOGIN PASSWORD '${password}';" > /dev/null

_pg "GRANT CONNECT ON DATABASE ${PG_DB} TO ${role_name};" > /dev/null

_pg "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${role_name};" > /dev/null



echo "{\"username\":\"${role_name}\",\"password\":\"${password}\"}"

}



dynamic_revoke_role() {

local role_name="$1"



if ! _pg "SELECT 1" > /dev/null 2>&1; then

echo "database unreachable" >&2

return 1

fi



_pg "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM ${role_name};" > /dev/null

_pg "REVOKE CONNECT ON DATABASE ${PG_DB} FROM ${role_name};" > /dev/null

_pg "DROP ROLE IF EXISTS ${role_name};" > /dev/null

return 0

}

