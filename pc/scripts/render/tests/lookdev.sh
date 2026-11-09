#!/usr/bin/env bash
# Look module look-dev renders under Xvfb + Mesa lavapipe (software Vulkan), holding the machine-wide render lock.
# Usage: pc/scripts/render/tests/lookdev.sh /abs/out_prefix "view1,view2" "variant@variant:key=v,key=v" [frames] [game args...]
#   e.g. lookdev.sh /tmp/x "spawn,kids" "base@soft:glow_intensity=0.3" 40 --quality=high
# RES=WxH (default 960x540). See scripts/render/tests/lookdev.gd for the variant syntax and the extra views.
set -u
OUT=${1:?out prefix}; VIEWS=${2:-spawn}; VARIANTS=${3:-base}; FRAMES=${4:-40}; shift $(( $# < 4 ? $# : 4 ))
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
EXTRA=(--autostart)
for a in "$@"; do [ "$a" = "--lookdev-menu" ] && EXTRA=(); done
timeout ${GODOT_TIMEOUT:-1500} xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path "$DIR" --rendering-driver vulkan \
  --resolution "$RES" -s res://scripts/render/tests/lookdev.gd -- --out="$OUT" --views="$VIEWS" --variants="$VARIANTS" \
  --frames="$FRAMES" "${EXTRA[@]}" "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_server|All audio drivers|^\s+at: (init_output|initialize)"
