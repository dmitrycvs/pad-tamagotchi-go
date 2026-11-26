#!/bin/sh
# Failover monitor (Lab 5): checks the primary, promotes the most advanced standby when it is gone.
#
#   failover.sh          run the monitor
#   failover.sh check    exit 0 while some node accepts writes (the container's health check)
#
# The name of the current primary is kept in /cluster/primary, which the nodes also read: it is
# written before pg_promote(), so an old primary that comes back sees it and rejoins as a standby.
set -u

NODES="${CLUSTER_NODES:-postgres-0,postgres-1,postgres-2}"
INTERVAL="${FAILOVER_CHECK_INTERVAL_SECONDS:-2}"
THRESHOLD="${FAILOVER_FAILURE_THRESHOLD:-3}"
GRACE="${FAILOVER_STARTUP_GRACE_SECONDS:-30}"
STATE_FILE="${STATE_FILE:-/cluster/primary}"
LOG_DIR="${LOG_DIR:-}"
INSTANCE="$(hostname)"
export PGUSER="${POSTGRES_USER:?}" PGPASSWORD="${POSTGRES_PASSWORD:?}" PGDATABASE=postgres PGCONNECT_TIMEOUT=2

if [ "${1:-}" = check ]; then
  exec psql -XAtq "host=$NODES port=5432 target_session_attrs=read-write" -c 'SELECT 1'
fi

log_file=""
if [ -n "$LOG_DIR" ] && mkdir -p "$LOG_DIR/postgres-failover" 2>/dev/null; then
  log_file="$LOG_DIR/postgres-failover/$INSTANCE.log"
fi

log() { # level message
  line="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$1\",\"service\":\"postgres-failover\",\"instance_id\":\"$INSTANCE\",\"message\":\"$2\"}"
  echo "$line"
  if [ -n "$log_file" ]; then echo "$line" >> "$log_file" 2>/dev/null; fi
}

alert() { # message; never blocks the checks and never prints the webhook URL
  [ -n "${DISCORD_WEBHOOK_URL:-}" ] || return 0
  (
    wget -q -T 5 -O /dev/null --header 'Content-Type: application/json' \
      --post-data "{\"username\":\"PostgreSQL failover\",\"content\":\"$1\"}" "$DISCORD_WEBHOOK_URL" 2>/dev/null \
      || log warn "Discord alert failed"
  ) &
}

query() { timeout 2 psql -XAtq "host=$1 port=5432" -c "$2" 2>/dev/null; }
now() { date +%s; }

# Asks every node at once, so a dead one does not delay the others: "node|f" accepts writes,
# "node|t|<replay position in bytes>|<everything received is replayed>" is a standby.
probe_nodes() {
  for node in $(echo "$NODES" | tr ',' ' '); do
    (
      row="$(query "$node" "SELECT CASE WHEN pg_is_in_recovery() THEN concat_ws('|', 't', (pg_last_wal_replay_lsn() - '0/0'::pg_lsn)::bigint, pg_last_wal_replay_lsn() >= COALESCE(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) ELSE 'f' END")"
      if [ -n "$row" ]; then echo "$node|$row"; fi
    ) &
  done
  wait
}

find_writable() { probe_nodes | awk -F'|' '$2 == "f" { print $1; exit }'; }

record_primary() {
  printf '%s' "$1" > "$STATE_FILE.tmp" && chmod 644 "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

failover() { # old primary
  # Standbys first replay everything they received (at most about 2 s), then their positions compare.
  tries=0
  while :; do
    nodes="$(probe_nodes)"
    tries=$((tries + 1))
    if [ "$tries" -ge 4 ] || ! echo "$nodes" | grep -q '|f$' || echo "$nodes" | grep -q '^[^|]*|f$'; then break; fi
    sleep 0.5
  done

  # Someone may have promoted a node already: adopt it instead of promoting another.
  writable="$(echo "$nodes" | awk -F'|' '$2 == "f" { print $1; exit }')"
  if [ -n "$writable" ]; then
    record_primary "$writable"
    log warn "Primary is now $writable (already promoted), was $1"
    return 0
  fi

  best="$(echo "$nodes" | awk -F'|' '$2 == "t"' | sort -t'|' -k3,3nr -k1,1 | head -n 1)"
  if [ -z "$best" ]; then
    log error "Primary $1 is down and no standby is reachable"
    return 1
  fi
  best_position="$(echo "$best" | cut -d'|' -f3)"
  best="$(echo "$best" | cut -d'|' -f1)"
  log info "Failover candidates (replay position): $(echo "$nodes" | awk -F'|' '{ printf "%s%s=%s", sep, $1, $3; sep = " " }')"

  record_primary "$best"
  if [ "$(timeout 35 psql -XAtq "host=$best port=5432" -c 'SELECT pg_promote(true, 30)' 2>/dev/null)" = t ]; then
    log warn "FAILOVER: promoted $best (replay position $best_position), $1 is down, took $(( $(now) - first_failure ))s since the first failed check"
    alert "PostgreSQL failover: **$1** is down, **$best** was promoted to primary."
    return 0
  fi
  log error "Promotion of $best failed, retrying"
  return 1
}

trap 'exit 0' TERM INT
started="$(now)" failures=0 first_failure=0 seen=no replicas=-1
log info "Failover monitor started nodes=$NODES interval=${INTERVAL}s threshold=$THRESHOLD"

while :; do
  tick="$(now)"
  primary="$(cat "$STATE_FILE" 2>/dev/null)"
  if [ -z "$primary" ]; then
    primary="$(find_writable)"
    if [ -n "$primary" ]; then
      record_primary "$primary"
      log info "Primary is $primary"
    fi
  elif [ "$(query "$primary" 'SELECT pg_is_in_recovery()')" = f ]; then
    if [ "$failures" -gt 0 ]; then log info "Primary $primary answers again"; fi
    failures=0 seen=yes
    count="$(query "$primary" "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming' AND application_name LIKE 'postgres-%'")"
    if [ -n "$count" ] && [ "$count" != "$replicas" ]; then
      replicas="$count"
      log info "Primary $primary has $replicas streaming replicas"
    fi
  else
    if [ "$failures" -eq 0 ]; then first_failure="$(now)"; fi
    failures=$((failures + 1))
    log warn "Primary $primary check failed ($failures/$THRESHOLD)"
    # While the whole stack starts, the primary may still be recovering: give it time.
    if [ "$failures" -ge "$THRESHOLD" ] && { [ "$seen" = yes ] || [ $(( $(now) - started )) -ge "$GRACE" ]; }; then
      if failover "$primary"; then failures=0 replicas=-1; fi
    fi
  fi
  # A check that took time (a dead host) does not stretch the interval.
  pause=$(( INTERVAL - ($(now) - tick) ))
  if [ "$pause" -gt 0 ]; then
    sleep "$pause" &
    wait $!
  fi
done
