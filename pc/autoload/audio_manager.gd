## STUB — audio module replaces it (see ARCHITECTURE_PC.md §Audio). Autoload "Audio".
## Public API (keep):
##   play(name: String, opts := {}) -> AudioHandle-like Dictionary/Object with stop(fade:=0.0), set_volume_db(db), set_position(v)
##       opts: position (Vector3, positional 3D sound), volume_db (float), pitch (float), bus (String), delay (float)
##   loop(name: String, opts := {}) -> same handle (looping until stop())
##   set_fear(v: float)  set_paused(paused: bool)  set_master_volume(v: float)  stop_all(fade := 0.3)
## Sound names = keys of res://assets/audio/manifest.json (63 recorded CC0 sounds) — see the web version's list.
extends Node

class SoundHandle:
	func stop(_fade := 0.0) -> void: pass
	func set_volume_db(_db: float) -> void: pass
	func set_position(_v: Vector3) -> void: pass

func play(_name: String, _opts := {}) -> SoundHandle: return SoundHandle.new()
func loop(_name: String, _opts := {}) -> SoundHandle: return SoundHandle.new()
func set_fear(_v: float) -> void: pass
func set_paused(_p: bool) -> void: pass
func set_master_volume(_v: float) -> void: pass
func stop_all(_fade := 0.3) -> void: pass
