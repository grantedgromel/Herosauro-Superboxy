#!/usr/bin/env bash
# Every chapter x seed, one Godot at a time. Usage (from the project dir):
#   tools/kidbot/run_all.sh [outdir] [seeds...]
# Writes <outdir>/<chapter>-<seed>.log and prints the KIDBOT summary lines.
# Extra kidbot args go in $KIDBOT_ARGS, e.g. KIDBOT_ARGS="--clumsy=2".
set -u
out="${1:-/tmp/kidbot}"; shift || true
seeds=("$@"); [ ${#seeds[@]} -eq 0 ] && seeds=(1 2 3)
mkdir -p "$out"
for ch in adamastor dragao pandas; do
  for s in "${seeds[@]}"; do
    timeout 1500 godot --headless --path . tools/kidbot/kidbot.tscn --fixed-fps 60 -- \
      --chapter="$ch" --seed="$s" ${KIDBOT_ARGS:-} > "$out/$ch-$s.log" 2>&1
    code=$?
    line=$(grep '^KIDBOT ' "$out/$ch-$s.log" || echo "KIDBOT chapter=$ch seed=$s completed=0 crashed exit=$code")
    echo "$line"
  done
done
