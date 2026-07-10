
#!/bin/bash

# Hand-rolled leader election

# Term numbers, votes, election timeouts, heartbeats

# No raft library, no etcd, built from scratch



CONSENSUS_DIR="${CONSENSUS_DIR:-/data/consensus}"

NODE_ID="${NODE_ID:-node1}"

NODE_PORT="${NODE_PORT:-8201}"

PEERS="${PEERS:-}"

ELECTION_TIMEOUT="${ELECTION_TIMEOUT:-3000}"

HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-1000}"



CURRENT_TERM=0

VOTED_FOR=""

CURRENT_ROLE="follower"

CURRENT_LEADER=""

LAST_HEARTBEAT=0



consensus_init() {

mkdir -p "$CONSENSUS_DIR"

[[ -f "$CONSENSUS_DIR/term" ]] && CURRENT_TERM=$(cat "$CONSENSUS_DIR/term")

[[ -f "$CONSENSUS_DIR/voted_for" ]] && VOTED_FOR=$(cat "$CONSENSUS_DIR/voted_for")

LAST_HEARTBEAT=$(date +%s%3N)

}



_consensus_persist() {

printf '%s' "$CURRENT_TERM" > "$CONSENSUS_DIR/term"

printf '%s' "$VOTED_FOR" > "$CONSENSUS_DIR/voted_for"

}



_consensus_peers() {

printf '%s' "$PEERS" | tr ',' '\n' | grep -v '^$'

}



_consensus_majority() {

local total=$(( $(_consensus_peers | wc -l) + 1 ))

echo $(( total / 2 + 1 ))

}



consensus_start_election() {

CURRENT_TERM=$((CURRENT_TERM + 1))

CURRENT_ROLE="candidate"

VOTED_FOR="$NODE_ID"

_consensus_persist

echo "Starting election term=$CURRENT_TERM"



local votes=1

local majority

majority=$(_consensus_majority)



while IFS= read -r peer; do

[[ -z "$peer" ]] && continue

local ph="${peer%:*}" pp="${peer##*:}"

local resp

resp=$(curl -s -X POST "http://${ph}:${pp}/internal/vote" \
-H "Content-Type: application/json" \
-d "{\"term\":$CURRENT_TERM,\"candidate_id\":\"$NODE_ID\"}" \
--connect-timeout 1 --max-time 2 2>/dev/null)

local granted

granted=$(echo "$resp" | python3 -c \
"import sys,json; print(json.loads(sys.stdin.read()).get('vote_granted',False))" 2>/dev/null)

[[ "$granted" == "True" ]] && votes=$((votes + 1))

done < <(_consensus_peers)



if [[ $votes -ge $majority ]]; then

_consensus_become_leader

else

CURRENT_ROLE="follower"

echo "Election failed votes=$votes need=$majority"

fi

}



_consensus_become_leader() {

CURRENT_ROLE="leader"

CURRENT_LEADER="$NODE_ID"

printf '%s' "$NODE_ID" > "$CONSENSUS_DIR/leader"

echo "Became leader term=$CURRENT_TERM"

_consensus_heartbeat_loop &

}



_consensus_heartbeat_loop() {

local interval=$(( HEARTBEAT_INTERVAL / 1000 ))

while [[ "$CURRENT_ROLE" == "leader" ]]; do

while IFS= read -r peer; do

[[ -z "$peer" ]] && continue

local ph="${peer%:*}" pp="${peer##*:}"

curl -s -X POST "http://${ph}:${pp}/internal/heartbeat" \
-H "Content-Type: application/json" \
-d "{\"term\":$CURRENT_TERM,\"leader_id\":\"$NODE_ID\"}" \
--connect-timeout 1 --max-time 2 > /dev/null 2>&1 &

done < <(_consensus_peers)

sleep "$interval"

done

}



consensus_handle_vote() {

local term="$1" candidate_id="$2"

local granted=false



if [[ $term -gt $CURRENT_TERM ]]; then

CURRENT_TERM=$term

CURRENT_ROLE="follower"

VOTED_FOR=""

_consensus_persist

fi



if [[ $term -eq $CURRENT_TERM ]] && \
([[ -z "$VOTED_FOR" ]] || [[ "$VOTED_FOR" == "$candidate_id" ]]); then

granted=true

VOTED_FOR="$candidate_id"

_consensus_persist

fi



echo "{\"term\":$CURRENT_TERM,\"vote_granted\":$granted}"

}



consensus_handle_heartbeat() {

local term="$1" leader_id="$2"

if [[ $term -ge $CURRENT_TERM ]]; then

CURRENT_TERM=$term

CURRENT_ROLE="follower"

CURRENT_LEADER="$leader_id"

LAST_HEARTBEAT=$(date +%s%3N)

printf '%s' "$leader_id" > "$CONSENSUS_DIR/leader"

_consensus_persist

fi

echo "{\"term\":$CURRENT_TERM,\"success\":true}"

}



consensus_election_watcher() {

local jitter=$(( RANDOM % 1500 ))

local timeout=$(( ELECTION_TIMEOUT + jitter ))



while true; do

sleep 1

[[ "$CURRENT_ROLE" == "leader" ]] && continue

local now elapsed

now=$(date +%s%3N)

elapsed=$(( now - LAST_HEARTBEAT ))

if [[ $elapsed -gt $timeout ]]; then

echo "Election timeout after ${elapsed}ms"

consensus_start_election

jitter=$(( RANDOM % 1500 ))

timeout=$(( ELECTION_TIMEOUT + jitter ))

LAST_HEARTBEAT=$(date +%s%3N)

fi

done

}



consensus_is_leader() { [[ "$CURRENT_ROLE" == "leader" ]]; }



consensus_get_leader() {

[[ -f "$CONSENSUS_DIR/leader" ]] && cat "$CONSENSUS_DIR/leader" || echo ""

}

