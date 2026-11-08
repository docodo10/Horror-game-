#!/usr/bin/env bash
# La Gardienne lookdev renders under Xvfb + Mesa lavapipe (software Vulkan), with the machine-wide render lock.
# Usage: pc/scripts/entity/tests/lookdev.sh /abs/out_prefix [views] [frames] [extra user args...]
#   views: lit,lit_close,lit_side,stairs_duck,dark,dark_close,jump,jump_lit   frames per view (default 10)
set -u
OUT=${1:?out prefix}; VIEWS=${2:-lit,dark,jump}; FRAMES=${3:-10}; shift $(( $# < 3 ? $# : 3 ))
RES=${RES:-960x540}
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
timeout ${GODOT_TIMEOUT:-900} xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path "$DIR" --rendering-driver vulkan \
  --resolution "$RES" -s res://scripts/entity/tests/lookdev.gd -- --out="$OUT" --views="$VIEWS" --frames="$FRAMES" "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_server|All audio drivers|^\s+at: (init_output|initialize)"
