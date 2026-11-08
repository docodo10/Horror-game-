## STUB — look module replaces it (ARCHITECTURE_PC.md §Look). Lights + WorldEnvironment for the level.
## Public API (keep): build(world) ; set_power(on) ; blowout() ; flicker(duration := 0.6, depth := 1.0) ; set_stress(v) ;
##   set_tv_light(on, intensity := 1.0) ; door_strip_occluded(v) ; set_menu_mode(on)
extends Node3D

func build(_world: Node) -> void: pass
func set_power(_on: bool) -> void: pass
func blowout() -> void: pass
func flicker(_d := 0.6, _depth := 1.0) -> void: pass
func set_stress(_v: float) -> void: pass
func set_tv_light(_on: bool, _i := 1.0) -> void: pass
func door_strip_occluded(_v: float) -> void: pass
func set_menu_mode(_on: bool) -> void: pass
