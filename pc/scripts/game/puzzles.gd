## STUB — gameplay module replaces it (ARCHITECTURE_PC.md §Scenario). Owns the scenario (port of src/game/Puzzles.js).
## Public API (keep): setup() (await), start(), stage: String, code: String, found: Dictionary, debug_goto(stage), reset_after_caught()
extends Node

var stage := "intro"
var code := "0000"
var found := {"duck": null, "horse": null, "clock": null, "tv": null}

func setup() -> void: process_mode = Node.PROCESS_MODE_PAUSABLE
func start() -> void:
	if Game.ui: Game.ui.set_objective("Explore le sous-sol.")
func debug_goto(_s: String) -> void: pass
func reset_after_caught() -> void: pass
