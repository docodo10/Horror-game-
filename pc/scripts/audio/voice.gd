## Audio module — one playing sound: a pooled AudioStreamPlayer3D / AudioStreamPlayer plus its mix state.
## Plain data; autoload/audio_manager.gd drives it every frame (gain, distance, occlusion shelf, fades, pitch glides).
## Reverberant sounds also own a "send" player: the same stream started in the same frame, centred, without distance
## attenuation (a uniform reverberant field, like the web graph's pre-panner send), feeding the wet-only reverb buses.
extends RefCounted

# reverb send ("twin" playback)
var twin: Node = null                # AudioStreamPlayer3D (head-locked, filterable) or AudioStreamPlayer
var twin3d := false
var space := -1                      # 0 = ReverbRoom, 1 = ReverbDark
var send := 0.0                      # send amount target (linear)
var send_cur := 0.0
var twin_bus := &""
var twin_last_db := 999.0
var twin_last_att := 999.0
var twin_last_hz := -1.0
var twin_shelf_db := 0.0             # occlusion-only shelf (smoothed)
var twin_shelf_lhz := 9.68

var name := ""
var def = null                       # sound_defs.gd SoundDef
var sample = null                    # audio_manager Sample (streams of this name)
var stream: AudioStream = null
var player: Node = null              # AudioStreamPlayer3D (positional / head-locked) or AudioStreamPlayer
var is3d := false                    # uses an AudioStreamPlayer3D
var head_locked := false             # 3D player glued to the listener (non-positional sound that needs a filter)
var loop := false
var entry = null                     # loop_entry.gd when this voice belongs to a shared loop
var idx := -1                        # index in the manager's voice list
var cat := "sfx"
var bus := &""
var bus_override := &""              # explicit bus from opts.bus (bypasses category/space routing)
var force_dry := false               # opts.dry: category bus without reverb (UI sounds)

# space
var pos := Vector3.ZERO
var attach: Node3D = null            # follows this node (+ attach_offset) every frame
var attach_offset := Vector3.ZERO
var zone := -1
var occ_hz := 20000.0                # occlusion low-pass target (Hz)
var occ_g := 1.0                     # occlusion gain target
var occ_g_cur := 1.0
var shelf_db := 0.0                  # current high-shelf gain dB (smoothed)
var shelf_lhz := 9.68                # current shelf corner, ln(Hz) (smoothed) — ln(16000)
var filter_hz := 0.0                 # user low-pass (0 = none)

# level / pitch
var v := 1.0                         # user volume (linear, 1 = default level)
var base_db := 0.0                   # manifest gain + jitter + opts.volume_db
var rate := 1.0                      # user playback rate
var rate_target := 1.0
var rate_tau := 0.0                  # glide time constant (s), 0 = immediate
var jr := 1.0                        # pitch jitter factor
var fade := 1.0                      # fade gain 0..1
var fade_target := 1.0
var fade_speed := 0.0                # per second

# lifetime
var delay := 0.0                     # seconds before the player starts
var offset := 0.0                    # start position (s)
var started := false
var stopping := false
var dead := false
var t0 := 0.0                        # start time (s, engine clock)
var grace := 0                       # frames to wait before trusting player.playing (3D players start on the next physics tick)

# last values pushed to the player (avoid redundant property writes)
var last_pos := Vector3(INF, INF, INF)
var last_db := 999.0
var last_pitch := -1.0
var last_shelf_db := 999.0
var last_shelf_hz := -1.0
