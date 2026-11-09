#!/usr/bin/env bash
# Rendered previews of the garderie (Xvfb + Mesa lavapipe software Vulkan), holding the machine-wide render lock
# shared with pc/tools/godot_shot.sh and tools/shot.cjs.
# Usage: pc/scripts/garderie/tests/garderie_shot.sh [--res 960x540] -- --out=/abs/prefix --views=hall,doorway [--frames=40]
set -u
RES=960x540
if [ "${1:-}" = "--res" ]; then RES=$2; shift 2; fi
[ "${1:-}" = "--" ] && shift
DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
LOCK="${TMPDIR:-/tmp}/lagardienne-browser.lock"
if [ -z "${NO_LOCK:-}" ]; then
  until mkdir "$LOCK" 2>/dev/null; do
    holder=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
    if [ -z "$holder" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then rm -rf "$LOCK"; continue; fi
    sleep 2
  done
  echo $$ > "$LOCK/pid"
  ( while sleep 60 && kill -0 $$ 2>/dev/null; do [ -d "$LOCK" ] && touch -c "$LOCK"; done ) & HEARTBEAT=$!
  trap 'kill $HEARTBEAT 2>/dev/null; [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK"' EXIT
fi
W=${RES%x*}; H=${RES#*x}
timeout ${GODOT_TIMEOUT:-1500} xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path "$DIR" --rendering-driver vulkan --resolution "$RES" \
  -s res://scripts/garderie/tests/preview.gd -- "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_server|All audio drivers|^\s+at: (init_output|initialize)|owner 'GeneratedLevel' inconsistent|^\s+at: add_child|GDScript backtrace|\[0\] assemble|\[1\] (build_level|run)|\[2\] run"
