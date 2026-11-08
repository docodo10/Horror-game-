#!/usr/bin/env bash
# UI module: render a SceneTree test script under Xvfb + lavapipe, holding the same machine-wide lock as
# pc/tools/godot_shot.sh (one heavy renderer at a time).
# Usage: pc/scripts/ui/tests/ui_render.sh 1280x720 res://scripts/ui/tests/menu_on_tv.gd --out=/abs/prefix [--pages=main,options]
set -u
RES=${1:-1280x720}; shift
SCRIPT=${1:?script}; shift
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
timeout ${GODOT_TIMEOUT:-900} xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path "$DIR" --rendering-driver vulkan --resolution "$RES" -s "$SCRIPT" -- "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_server|All audio drivers|^\s+at: (init_output|initialize)"
