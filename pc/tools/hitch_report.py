#!/usr/bin/env python3
"""Report for tools/hitch_hunt.gd CSVs: per step and lap -> frames, median / max frame time, spikes, blocking pipeline
compilations, and the jump in draw calls / primitives (shadow re-renders). Usage: hitch_report.py file.csv [--all]"""
import csv, statistics, sys
from collections import OrderedDict

path = sys.argv[1]
show_all = "--all" in sys.argv
rows = list(csv.DictReader(open(path)))
for r in rows:
    for k in ("lap", "frame", "draw_calls", "prims", "objects", "c_draw", "c_surface", "c_mesh", "c_spec", "c_canvas", "vmem_mb"):
        r[k] = int(r[k])
    r["ms"] = float(r["ms"])

steps = OrderedDict()
for r in rows:
    steps.setdefault((r["step"], r["lap"]), []).append(r)

all_ms = [r["ms"] for r in rows]
gmed = statistics.median(all_ms)
print(f"{path}: {len(rows)} frames, median {gmed:.1f} ms, p99 {sorted(all_ms)[int(len(all_ms)*0.99)]:.1f} ms, max {max(all_ms):.1f} ms")
for lap in (1, 2):
    L = [r for r in rows if r["lap"] == lap]
    if not L: continue
    ms = sorted(r["ms"] for r in L)
    med = statistics.median(ms)
    sp = [r for r in L if r["ms"] > 2.0 * med and r["ms"] > med + 8.0]
    print(f"  lap {lap}: {len(L)} frames, median {med:.1f} ms, max {ms[-1]:.1f} ms, spikes (>2x median) {len(sp)}, "
          f"blocking compiles {sum(r['c_draw'] for r in L)}, background compiles {sum(r['c_surface'] + r['c_mesh'] + r['c_spec'] for r in L)}, "
          f"canvas {sum(r['c_canvas'] for r in L)}")

print(f"\n{'step':30s} lap  n   med    max  x   draw surf spec  prims med -> max        dc med->max   vmem")
names = OrderedDict((k[0], 1) for k in steps)
for name in names:
    for lap in (1, 2):
        S = steps.get((name, lap))
        if not S: continue
        ms = [r["ms"] for r in S]
        med = statistics.median(ms)
        mx = max(ms)
        pr = [r["prims"] for r in S]
        dc = [r["draw_calls"] for r in S]
        cd = sum(r["c_draw"] for r in S)
        cs = sum(r["c_surface"] + r["c_mesh"] for r in S)
        cp = sum(r["c_spec"] for r in S)
        ratio = mx / med if med > 0 else 0
        flag = ""
        if cd > 0: flag += " COMPILE"
        if ratio > 2.2 and mx > med + 8: flag += " SPIKE"
        pmed = statistics.median(pr)
        if pmed > 0 and max(pr) > 1.6 * pmed and max(pr) - pmed > 150000: flag += " REDRAW"
        if not show_all and not flag and lap == 2: continue
        print(f"{name[:30]:30s} {lap}  {len(S):3d} {med:6.1f} {mx:6.1f} {ratio:3.1f} {cd:5d} {cs:4d} {cp:4d}  "
              f"{int(pmed):8d} -> {max(pr):8d}  {int(statistics.median(dc)):5d}->{max(dc):5d}  {S[-1]['vmem_mb']:5d}{flag}")
