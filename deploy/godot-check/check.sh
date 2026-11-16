#!/bin/sh
# One round of the Godot check: the runs the Rust check rejected
# (backend.godot_pending_runs), replayed with the GDScript sim, the verdicts
# written back (backend.godot_record_results). Needs DATABASE_URL.
set -eu
# A new pod's address reaches the cluster's network rules a moment after it
# starts (k3s's kube-router); until then Postgres refuses it. Wait for it.
for i in $(seq 1 30); do
  psql "$DATABASE_URL" -At -c "select 1" >/dev/null 2>&1 && break
  sleep 2
done
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -At -c "select backend.godot_pending_runs(200)" > /tmp/pending.json
if [ "$(cat /tmp/pending.json)" = "[]" ]; then
  echo "nothing to check"
  exit 0
fi
godot --headless --path /game -s res://server/verify_batch.gd -- /tmp/pending.json /tmp/results.json
# psql fills in :'results' (quoted safely) only for commands read from stdin.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -At -v results="$(cat /tmp/results.json)" <<'SQL'
select backend.godot_record_results(:'results'::jsonb);
SQL
