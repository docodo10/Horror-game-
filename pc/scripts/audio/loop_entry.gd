## Audio module — a shared looping sound: one voice, many owners (port of the web LoopEntry).
## Audio.loop(name) is idempotent per name (+ position within 1 m; `single` defs share one instance whatever the
## position): every caller gets its own handle, the voice stops when every handle has been stopped.
extends RefCounted

var name := ""
var def = null                       # sound_defs.gd SoundDef
var refs := 0
var voice = null                     # voice.gd while sounding
var stopped := false
var volume := 1.0
var volume_db := 0.0                 # opts.volume_db
var rate := 1.0
var filter_hz := 0.0
var unique := false
var offset := -1.0                   # start offset (s); < 0 = default (random when def.rnd)
var fade_in := 0.6
var positional := true               # false when opts.positional == false
var has_position := false
var position := Vector3.ZERO
var follow := false                  # follows the creature (lullaby) until an explicit position is given
var attach: Node3D = null
var attach_offset := Vector3.ZERO
var bus := ""                        # opts.bus
var dry := false                     # opts.dry
var retry_t := 0.0                   # waits before re-trying to start when no player was free
