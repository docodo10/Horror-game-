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
  until mkdir "$LOCK" 2>/dev/null; do
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +25 2>/dev/null)" ]; then rm -rf "$LOCK"; continue; fi
    sleep 2
  done
  echo $$ > "$LOCK/pid"; trap 'rm -rf "$LOCK"' EXIT
fi
W=${RES%x*}; H=${RES#*x}
timeout ${GODOT_TIMEOUT:-900} xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path "$DIR" --rendering-driver vulkan --resolution "$RES" -- "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_server|All audio drivers|^\s+at: (init_output|initialize)" 
