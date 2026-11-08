#!/usr/bin/env bash
# Render the Godot game under Xvfb + Mesa lavapipe (software Vulkan) and save screenshots.
# Usage: pc/tools/godot_shot.sh [--res 1280x720] -- <game user args, e.g. --shot=/abs/out.png --cam=0.25,0,1.6,0,-3 --quality=high>
# Holds the same machine-wide lock as tools/shot.cjs (one heavy renderer at a time). NO_LOCK=1 skips it.
set -u
RES=1280x720
if [ "${1:-}" = "--res" ]; then RES=$2; shift 2; fi
[ "${1:-}" = "--" ] && shift
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${TMPDIR:-/tmp}/lagardienne-browser.lock"
if [ -z "${NO_LOCK:-}" ]; then
  # Break the lock only if its holder is dead (or never wrote its pid within 2 min); keep ours fresh every minute
  # so older copies of the harness (which break locks with mtime > 25 min) never break a live one.
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
timeout ${GODOT_TIMEOUT:-900} xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path "$DIR" --rendering-driver vulkan --resolution "$RES" -- "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_server|All audio drivers|^\s+at: (init_output|initialize)" 
