#!/usr/bin/env bash
# Entrypoint of postgres-0, postgres-1 and postgres-2 (Lab 5 replication). Decides on every start
# whether this node is the primary, a standby that clones itself, or an old primary that rejoins.
#
# /cluster/primary names the current primary. Only the failover monitor writes it (db/failover).
#   no file yet        first start: $BOOTSTRAP_NODE initializes the cluster, the others clone it
#   names this node    start normally
#   names another node this node is a standby; an old primary is rewound (pg_rewind) or cloned again
#
# A guard in the background keeps the replication role and slots in place, stops this server if it
# still accepts writes after another node was promoted (so there are never two primaries), and
# rewinds or clones a standby that cannot follow the primary any more.
set -euo pipefail

NODE_NAME="${NODE_NAME:-$(hostname)}"
CLUSTER_NODES="${CLUSTER_NODES:-postgres-0,postgres-1,postgres-2}"
BOOTSTRAP_NODE="${BOOTSTRAP_NODE:-postgres-0}"
STATE_FILE="${STATE_FILE:-/cluster/primary}"
REPLICATION_USER=replicator
PASSFILE=/var/lib/postgresql/.pgpass
# Left for the next start by the guard: "rewind" or "clone".
REJOIN_FILE=/var/lib/postgresql/.rejoin
REWOUND_FILE=/var/lib/postgresql/.rewound
# Starts since this server last answered; the guard resets it.
STARTS_FILE=/var/lib/postgresql/.starts
: "${POSTGRES_USER:?}" "${POSTGRES_PASSWORD:?}" "${POSTGRES_REPLICATION_PASSWORD:?}" "${PGDATA:?}"
export PGCONNECT_TIMEOUT=3

log() { echo "[node $NODE_NAME] $*"; }
current_primary() { cat "$STATE_FILE" 2>/dev/null || true; }
slot_of() { echo "${1//-/_}"; }
has_data() { [ -s "$PGDATA/PG_VERSION" ]; }
escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/:/\\:/g'; }

(
  umask 077
  printf '*:*:*:%s:%s\n*:*:*:%s:%s\n' \
    "$REPLICATION_USER" "$(escape "$POSTGRES_REPLICATION_PASSWORD")" \
    "$(escape "$POSTGRES_USER")" "$(escape "$POSTGRES_PASSWORD")" > "$PASSFILE"
)
chown postgres:postgres "$PASSFILE"
mkdir -p "$PGDATA"
chown postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"

# All three hosts, primary only: standbys find a promoted primary on their own.
REPLICATION_CONNINFO="host=$CLUSTER_NODES port=5432 user=$REPLICATION_USER passfile=$PASSFILE application_name=$NODE_NAME target_session_attrs=read-write connect_timeout=3"
ADMIN_CONNINFO="host=$CLUSTER_NODES port=5432 user=$POSTGRES_USER dbname=postgres passfile=$PASSFILE target_session_attrs=read-write connect_timeout=3"

primary_reachable() { gosu postgres psql -XAtq -d "$ADMIN_CONNINFO" -c 'SELECT 1' >/dev/null 2>&1; }

wait_for_primary() {
  local waited=0
  until primary_reachable; do
    if (( waited % 10 == 0 )); then log "waiting for a primary among $CLUSTER_NODES"; fi
    sleep 1
    waited=$((waited + 1))
  done
}

clone() {
  local attempt=1
  while true; do
    wait_for_primary
    find "$PGDATA" -mindepth 1 -delete
    log "cloning the primary with pg_basebackup, attempt $attempt"
    if gosu postgres pg_basebackup -d "$REPLICATION_CONNINFO" -D "$PGDATA" -R -X stream \
        -S "$(slot_of "$NODE_NAME")" --checkpoint=fast; then
      log "clone finished, starting as a standby"
      rm -f "$REWOUND_FILE"
      return
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
}

rejoin() {
  wait_for_primary
  # pg_rewind first finishes crash recovery in single-user mode, which reads only the configuration
  # files: the settings it needs are on this container's command line otherwise.
  printf '%s
' "wal_log_hints = 'on'" "max_prepared_transactions = '64'" "max_connections = '200'" >> "$PGDATA/postgresql.auto.conf"
  # A checkpoint on the new primary records its timeline where pg_rewind looks for it.
  gosu postgres psql -XAtq -d "$ADMIN_CONNINFO" -c 'CHECKPOINT' >/dev/null || true
  if gosu postgres pg_rewind --target-pgdata="$PGDATA" --source-server="$ADMIN_CONNINFO" --progress; then
    gosu postgres touch "$PGDATA/standby.signal"
    touch "$REWOUND_FILE"
    log "pg_rewind finished, starting as a standby"
  else
    log "pg_rewind failed, cloning again"
    clone
  fi
}

sql() { gosu postgres psql -XAtq -U "$POSTGRES_USER" -d postgres "$@"; }

ensure_role() {
  # :'secret' keeps the password out of the SQL text; \gexec runs what the query returns.
  sql -v secret="$POSTGRES_REPLICATION_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE replicator WITH REPLICATION LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') \gexec
ALTER ROLE replicator WITH REPLICATION LOGIN PASSWORD :'secret';
SQL
}

# Every node keeps one slot per other node, so a promoted standby can serve the rest at once. On a
# standby an unused slot must not hold WAL back, so one left over from an earlier term is recreated.
ensure_slots() {
  local node slot
  sql -c "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots
          WHERE pg_is_in_recovery() AND NOT active AND slot_type = 'physical' AND NOT temporary AND restart_lsn IS NOT NULL" >/dev/null
  for node in ${CLUSTER_NODES//,/ }; do
    if [ "$node" = "$NODE_NAME" ]; then continue; fi
    slot="$(slot_of "$node")"
    sql -c "SELECT pg_create_physical_replication_slot('$slot')
            WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = '$slot')" >/dev/null
  done
}

# A rewind that did not help is followed by a full clone.
next_rejoin() { if [ -f "$REWOUND_FILE" ]; then echo clone; else echo rewind; fi; }

guard() {
  set +e
  local role_done=no recovery primary position last_position="" streaming stuck=0
  while sleep 2; do
    recovery="$(sql -c 'SELECT pg_is_in_recovery()' 2>/dev/null)" || continue
    rm -f "$STARTS_FILE"
    primary="$(current_primary)"
    if [ "$recovery" = f ] && [ -n "$primary" ] && [ "$primary" != "$NODE_NAME" ]; then
      log "FENCED: $primary is the primary now, stopping this server so it rejoins as a standby"
      gosu postgres pg_ctl -D "$PGDATA" -m fast stop >/dev/null 2>&1
      return
    fi
    if [ "$recovery" = f ] && [ "$role_done" = no ]; then
      ensure_role >/dev/null 2>&1 && role_done=yes
    fi
    ensure_slots 2>/dev/null

    # A standby that received WAL the promoted node never had (or whose WAL is gone on the primary)
    # retries forever. No streaming and no progress for 10 checks while a primary answers: start over.
    if [ "$recovery" = t ]; then
      position="$(sql -c 'SELECT pg_last_wal_replay_lsn()' 2>/dev/null)"
      streaming="$(gosu postgres psql -XAtq -d "$ADMIN_CONNINFO" -c "SELECT count(*) FROM pg_stat_replication WHERE application_name = '$NODE_NAME' AND state = 'streaming'" 2>/dev/null)"
      if [ "$streaming" = 0 ] && [ "$position" = "$last_position" ]; then
        stuck=$((stuck + 1))
      elif [ "$streaming" = 1 ]; then
        stuck=0
        rm -f "$REWOUND_FILE"
      fi
      last_position="$position"
      if [ "$stuck" -ge 10 ]; then
        next_rejoin > "$REJOIN_FILE"
        log "cannot follow the primary from $position, restarting to $(cat "$REJOIN_FILE")"
        gosu postgres pg_ctl -D "$PGDATA" -m fast stop >/dev/null 2>&1
        return
      fi
    fi
  done
}

primary="$(current_primary)"
todo="$(cat "$REJOIN_FILE" 2>/dev/null || true)"
rm -f "$REJOIN_FILE"
starts=$(( $(cat "$STARTS_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$starts" > "$STARTS_FILE"
# A diverged standby does not even start ("requested timeline is not a child of this server's history").
if [ "$starts" -ge 3 ] && [ -f "$PGDATA/standby.signal" ] && [ -n "$primary" ] && [ "$primary" != "$NODE_NAME" ] && primary_reachable; then
  todo="$(next_rejoin)"
fi
if has_data; then
  if [ "$todo" = rewind ]; then
    log "this standby diverged from the primary: rejoining"
    rejoin
  elif [ "$todo" = clone ]; then
    clone
  elif [ -f "$PGDATA/standby.signal" ]; then
    log "starting as a standby"
  elif [ -n "$primary" ] && [ "$primary" != "$NODE_NAME" ]; then
    log "this node was the primary and $primary took over: rejoining as a standby"
    rejoin
  else
    log "starting as the primary"
  fi
elif [ -z "$primary" ] && [ "$NODE_NAME" = "$BOOTSTRAP_NODE" ]; then
  log "first start: initializing the cluster"
else
  # Never initialize over a running cluster: a primary that lost its volume waits for the monitor to
  # promote a standby, then clones it.
  if [ "$primary" = "$NODE_NAME" ]; then log "the primary's data is gone, waiting for another node to be promoted"; fi
  clone
fi

# Detached from this shell, so it is not a child of the postmaster that exec starts below.
( ( guard ) & )

exec docker-entrypoint.sh "$@" \
  -c "cluster_name=$NODE_NAME" \
  -c "primary_conninfo=$REPLICATION_CONNINFO" \
  -c "primary_slot_name=$(slot_of "$NODE_NAME")"
