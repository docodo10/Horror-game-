#!/usr/bin/env python3
"""Cuts the trailer: gameplay recorded by trailer_shots.gd (one .avi + .log per run), the text cards of make_cards.py,
lower-third labels over the footage, the game's own audio under a music bed made of the game's sounds.

    python3 pc/tools/trailer/build_trailer.py --src /abs/final --cards /abs/cards --work /abs/work --out /abs/trailer.mp4
    [--preview]   half resolution, fast encode (to check the cut)

Everything is 60 fps; positions are frames. A shot range is (anchor, offset, length): anchor "start" / "end" of the
shot or one of its "[mark]" lines.
"""
import argparse
import json
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FPS = 60
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")
FONTS = os.path.join(ROOT, "pc", "assets", "fonts")
SANS = os.path.join(FONTS, "atkinson_hyperlegible", "AtkinsonHyperlegible-Regular.ttf")
SERIF = os.path.join(FONTS, "gelasio", "Gelasio-Regular.ttf")

RUN_OF = {"e": "etage", "b": "basement", "g": "garderie"}

# ----------------------------------------------------------------------------------------------- the cut
# kind, name, [range], options: gain (dB on the game audio), fin / fout (video fade frames), label (lower third)
EDL = [
    ("card", "c1_date", None, {"id": "date"}),
    ("shot", "b_menu", ("start", 62, 398), {"fin": 14, "gain": -2, "label": ("CHAPITRE 1", "LE SOUS-SOL", 215)}),
    ("card", "c2_fermee", None, {"id": "fermee"}),
    ("shot", "g_hall", ("start", 20, 280), {"label": ("LA GARDERIE", "fermée depuis novembre 1994", 40)}),
    ("shot", "g_slide", ("start", 100, 105), {}),
    ("shot", "g_dortoir", ("start", 40, 250), {}),
    ("card", "c3_enfants", None, {"id": "enfants"}),
    ("shot", "b_walk", ("start", 250, 200), {}),
    ("shot", "g_bureau", ("start", 70, 190), {"gain": -5}),
    ("card", "c4_restee", None, {"id": "restee"}),
    ("shot", "e_hall", ("start", 20, 250), {"label": ("CHAPITRE 2", "L’ÉTAGE", 30)}),
    ("shot", "b_dark", ("start", 20, 250), {}),
    ("card", "c5_bruit", None, {"id": "bruit"}),
    ("shot", "e_salon", ("start", 150, 250), {}),
    ("shot", "g_wc", ("start", 60, 150), {}),
    ("shot", "g_wc", ("end", -175, 95), {}),
    ("card", "c6_yeux", None, {"id": "yeux"}),
    ("shot", "e_key", ("key", -20, 60), {"id": "key"}),
    ("shot", "e_key", ("awake", -10, 245), {}),
    ("shot", "b_her", ("start", 50, 120), {"id": "montage"}),
    ("shot", "e_key", ("seen2", 45, 0), {"upto": "caught", "extra": 34}),
    ("shot", "b_her", ("end", -78, 48), {"gain": 2}),
    ("card", "c7_title", None, {"id": "title"}),
]

# music and effects laid over the cut: (sound file under assets/audio, where, level, options)
#   where: (id of an EDL entry, frame offset)      level: target mean dBFS of the layer
SOUND = [
    ("player_music/ambience_drone.mp3", ("date", 0), -31, {"loop": True, "until": ("title", 0), "fin": 2.0, "fout": 0.4}),
    ("player_music/wind_outside.mp3", ("date", 0), -34, {"loop": True, "until": ("fermee", 0), "fin": 1.0, "fout": 1.0}),
    ("footsteps/land_thump_1.mp3", ("fermee", 30), -15, {"rate": 0.45, "echo": True}),
    ("etage/piano_sting_1.mp3", ("fermee", 30), -24, {}),
    ("footsteps/land_thump_2.mp3", ("enfants", 30), -15, {"rate": 0.45, "echo": True}),
    ("creature/giggle_1.mp3", ("enfants", 96), -27, {"echo": True}),
    ("footsteps/land_thump_1.mp3", ("restee", 30), -13, {"rate": 0.4, "echo": True}),
    ("etage/piano_sting_2.mp3", ("restee", 30), -21, {}),
    ("etage/etage_theme.mp3", ("restee", 0), -29, {"until": ("yeux", 100), "fin": 3.0, "fout": 0.5}),
    ("footsteps/land_thump_2.mp3", ("bruit", 24), -14, {"rate": 0.45, "echo": True}),
    ("footsteps/land_thump_1.mp3", ("yeux", 24), -12, {"rate": 0.4, "echo": True}),
    ("player_music/heartbeat.mp3", ("yeux", 30), -20, {"loop": True, "until": ("montage", 0), "fin": 0.6, "fout": 0.1}),
    ("player_music/heartbeat_fast.mp3", ("montage", 0), -17, {"loop": True, "until": ("title", 0), "fout": 0.05}),
    ("player_music/chase_music.mp3", ("montage", 0), -19, {"until": ("title", 0), "fin": 0.3, "fout": 0.03}),
    ("player_music/stinger_1.mp3", ("title", 0), -13, {}),
    ("footsteps/land_thump_1.mp3", ("title", 0), -11, {"rate": 0.35, "echo": True}),
    ("garderie/music_box.mp3", ("title", 110), -27, {"dur": 8.0, "fin": 1.5, "fout": 2.5, "echo": True}),
    ("creature/giggle_2.mp3", ("title", 535), -25, {"echo": True}),
]


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.stderr.write(" ".join(cmd) + "\n" + r.stderr[-3000:] + "\n")
        raise SystemExit(1)
    return r


def read_logs(src):
    shots, marks = {}, {}
    for f in os.listdir(src):
        if not f.endswith(".log"):
            continue
        for line in open(os.path.join(src, f), errors="replace"):
            m = re.match(r"\[shot\] (\S+) (\d+) (\d+)", line)
            if m:
                shots[m.group(1)] = (int(m.group(2)), int(m.group(3)))
            m = re.match(r"\[mark\] (\S+) (\S+).* (\d+)\s*$", line)
            if m:
                marks[(m.group(1), m.group(2))] = int(m.group(3))
    return shots, marks


def frames_of(path):
    r = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets", "-show_entries", "stream=nb_read_packets",
             "-of", "csv=p=0", path])
    return int(r.stdout.strip().split(",")[0])


def label_png(path, small, big, w, h):
    """Lower third: a thin rule, a small tracked line and a serif line, bottom left."""
    s = h / 1080.0
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(sh)
    f1 = ImageFont.truetype(SANS, 27 * s)
    f2 = ImageFont.truetype(SERIF, 50 * s)
    x, y = 110 * s, h - 235 * s

    def tracked(dr, xy, text, font, track, fill):
        cx = xy[0]
        for ch in text:
            dr.text((cx, xy[1]), ch, font=font, fill=fill)
            cx += font.getlength(ch) + track
    tracked(d, (x, y), small, f1, 7 * s, 255)
    d.text((x - 2 * s, y + 44 * s), big, font=f2, fill=255)
    d.rectangle([x, y - 16 * s, x + 70 * s, y - 14 * s], fill=255)
    shadow = sh.filter(ImageFilter.GaussianBlur(7 * s))
    img.paste((0, 0, 0, 255), mask=shadow.point(lambda v: min(255, int(v * 1.5))))
    top = Image.new("RGBA", (w, h), (236, 228, 212, 255))
    img.paste(top, mask=sh)
    red = Image.new("L", (w, h), 0)
    ImageDraw.Draw(red).rectangle([x, y - 16 * s, x + 70 * s, y - 14 * s], fill=255)
    img.paste((200, 32, 24, 255), mask=red)
    img.save(path)


def mean_db(path):
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"mean_volume: (-?[\d.]+) dB", r.stderr)
    return float(m.group(1)) if m else -30.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--cards", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--mbps", type=float, default=7.0)
    ap.add_argument("--skip-missing", action="store_true", help="leave out shots that were not recorded (to test the cut early)")
    a = ap.parse_args()
    os.makedirs(a.work, exist_ok=True)
    shots, marks = read_logs(a.src)
    W, H = (960, 540) if a.preview else (1920, 1080)
    crf, preset = ("20", "veryfast") if a.preview else ("10", "fast")
    to709 = "scale=%d:%d:flags=lanczos:in_color_matrix=bt601:out_color_matrix=bt709:in_range=%s:out_range=tv,format=yuv420p"
    tags = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv"]

    segs = []          # (video path, audio path, frames)
    starts = []        # first frame of each EDL entry in the cut
    total = 0
    for i, (kind, name, rng, opt) in enumerate(EDL):
        v = os.path.join(a.work, "seg%02d.mp4" % i)
        au = os.path.join(a.work, "seg%02d.wav" % i)
        starts.append(total)
        if kind == "shot" and name not in shots and a.skip_missing:
            continue
        if kind == "card":
            src = os.path.join(a.cards, name + ".mp4")
            n = int(opt.get("n", frames_of(src)))
            run(["ffmpeg", "-y", "-v", "error", "-i", src, "-frames:v", str(n), "-vf", to709 % (W, H, "tv"), "-r", str(FPS),
                 "-c:v", "libx264", "-preset", preset, "-crf", crf] + tags + [v])
            run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", "%.6f" % (n / FPS),
                 "-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le", au])    # same sample format as the shots: they are concatenated
        else:
            if name not in shots:
                raise SystemExit("shot %s was not recorded" % name)
            s0, s1 = shots[name]
            anchor, off, n = rng
            base = s0 if anchor == "start" else s1 if anchor == "end" else marks[(name, anchor)]
            f0 = base + off
            if "upto" in opt:
                n = marks[(name, opt["upto"])] + int(opt.get("extra", 0)) - f0
            if f0 < s0 - 2 or f0 + n > s1 + 2:
                print("warning: %s %s leaves the shot (%d..%d of %d..%d)" % (name, rng, f0, f0 + n, s0, s1))
            src = os.path.join(a.src, RUN_OF[name[0]] + ".avi")
            vf = [to709 % (W, H, "pc")]
            inputs = ["-ss", "%.6f" % (f0 / FPS), "-i", src]
            fc = None
            if opt.get("fin"):
                vf.append("fade=t=in:st=0:d=%.4f" % (opt["fin"] / FPS))
            if opt.get("fout"):
                vf.append("fade=t=out:st=%.4f:d=%.4f" % ((n - opt["fout"]) / FPS, opt["fout"] / FPS))
            if opt.get("label"):
                small, big, at = opt["label"]
                png = os.path.join(a.work, "label%02d.png" % i)
                label_png(png, small, big, W, H)
                t0 = at / FPS
                inputs += ["-loop", "1", "-i", png]
                fc = ("[0:v]%s[b];[1:v]format=rgba,fade=t=in:st=%.3f:d=0.6:alpha=1,fade=t=out:st=%.3f:d=0.5:alpha=1[l];"
                      "[b][l]overlay=x='-28*(1-min(1,max(0,(t-%.3f)/0.9)))':y=0:format=auto,format=yuv420p[v]"
                      % (",".join(vf), t0, t0 + 2.6, t0))
            cmd = ["ffmpeg", "-y", "-v", "error"] + inputs
            if fc:
                cmd += ["-filter_complex", fc, "-map", "[v]"]
            else:
                cmd += ["-vf", ",".join(vf), "-map", "0:v"]
            cmd += ["-frames:v", str(n), "-r", str(FPS), "-c:v", "libx264", "-preset", preset, "-crf", crf] + tags + [v]
            run(cmd)
            d = n / FPS
            g = float(opt.get("gain", 0))
            run(["ffmpeg", "-y", "-v", "error", "-ss", "%.6f" % (f0 / FPS), "-i", src, "-t", "%.6f" % d, "-map", "0:a",
                 "-af", "volume=%.1fdB,afade=t=in:st=0:d=0.05,afade=t=out:st=%.4f:d=0.06,apad=whole_dur=%.6f" % (g, d - 0.06, d),
                 "-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le", "-t", "%.6f" % d, au])
        segs.append((v, au, n))
        total += n
        print("seg %02d %-10s %-10s %4d f  at %6.2f s" % (i, kind, name, n, starts[i] / FPS), flush=True)
    starts.append(total)
    dur = total / FPS
    print("total %.2f s (%d frames)" % (dur, total))

    lst = os.path.join(a.work, "v.txt")
    open(lst, "w").write("".join("file '%s'\n" % s[0] for s in segs))
    video = os.path.join(a.work, "video.mp4")
    run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", video])
    lst = os.path.join(a.work, "a.txt")
    open(lst, "w").write("".join("file '%s'\n" % s[1] for s in segs))
    game = os.path.join(a.work, "game.wav")
    run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c:a", "pcm_s24le", game])

    ids = {e[3]["id"]: k for k, e in enumerate(EDL) if "id" in e[3]}

    def when(w):
        return (starts[ids[w[0]]] + w[1]) / FPS

    inputs = ["-i", game]
    chains = ["[0:a]volume=%.1fdB[g]" % (-21.0 - mean_db(game))]     # the game's own sound: -21 dB mean
    mix = ["[g]"]
    for k, (f, at, level, o) in enumerate(SOUND):
        path = os.path.join(AUDIO, f)
        t0 = when(at)
        length = None
        if "until" in o:
            length = when(o["until"]) - t0
        if "dur" in o:
            length = float(o["dur"])
        if o.get("loop"):
            inputs += ["-stream_loop", "-1", "-i", path]
        else:
            inputs += ["-i", path]
        c = ["aresample=48000", "aformat=channel_layouts=stereo"]
        if "rate" in o:
            c += ["asetrate=%d" % int(48000 * o["rate"]), "aresample=48000"]
        if length is not None:
            c.append("atrim=0:%.4f" % length)
        c.append("volume=%.1fdB" % (level - mean_db(path)))
        if o.get("echo"):
            c.append("aecho=0.8:0.7:90|210:0.35|0.2")
        if o.get("fin"):
            c.append("afade=t=in:st=0:d=%.3f" % o["fin"])
        if o.get("fout") and length is not None:
            c.append("afade=t=out:st=%.4f:d=%.3f" % (max(0.0, length - o["fout"]), o["fout"]))
        c.append("adelay=%d:all=1" % int(t0 * 1000))
        chains.append("[%d:a]%s[s%d]" % (k + 1, ",".join(c), k))
        mix.append("[s%d]" % k)
    chains.append("%samix=inputs=%d:normalize=0:duration=longest,volume=-7dB,atrim=0:%.4f,afade=t=out:st=%.4f:d=0.5[m]"
                  % ("".join(mix), len(mix), dur, dur - 0.5))
    mixed = os.path.join(a.work, "mix.wav")
    run(["ffmpeg", "-y", "-v", "error"] + inputs + ["-filter_complex", ";".join(chains), "-map", "[m]", "-c:a", "pcm_s24le", mixed])
    # two-pass loudness: measure, then one linear gain to -16 LUFS (no pumping)
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", mixed, "-af", "loudnorm=I=-16:TP=-1.5:LRA=14:print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    j = json.loads(r.stderr[r.stderr.rindex("{"):r.stderr.rindex("}") + 1])
    print("mix loudness %s LUFS, true peak %s dB" % (j["input_i"], j["input_tp"]))
    gain = min(-16.0 - float(j["input_i"]), -1.5 - float(j["input_tp"]) + 6.0)
    final_a = os.path.join(a.work, "final.wav")
    run(["ffmpeg", "-y", "-v", "error", "-i", mixed, "-af", "volume=%.2fdB,alimiter=limit=0.84:attack=3:release=60" % gain,
         "-c:a", "pcm_s24le", final_a])

    if a.preview:
        venc = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "24"]
    else:
        br = "%dk" % int(a.mbps * 1000)
        venc = ["-c:v", "libx264", "-preset", "slow", "-b:v", br, "-maxrate", "%dk" % int(a.mbps * 1600), "-bufsize",
                "%dk" % int(a.mbps * 3000), "-profile:v", "high", "-level", "4.2", "-x264-params", "aq-mode=3"]
    run(["ffmpeg", "-y", "-v", "error", "-i", video, "-i", final_a] + venc + tags +
        ["-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-shortest", a.out])
    print("wrote", a.out, "%.1f MB" % (os.path.getsize(a.out) / 1e6))


if __name__ == "__main__":
    main()
