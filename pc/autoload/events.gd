## Global signal bus (autoload "Events"). Emit with Events.noise.emit(...), listen with Events.noise.connect(...).
extends Node

signal noise(position: Vector3, loudness: float, source: String)        # player, gameplay -> entity
signal power_changed(on: bool)                                            # world.set_power -> lighting, audio, props
signal player_flashlight(has: bool, on: bool, battery: float)             # player -> ui, audio
signal player_stamina(value: float, exhausted: bool, breath: float)       # player -> ui, audio
signal player_hide(hidden: bool, spot_id: String)                         # player -> entity, ui, audio
signal player_bump(tag: String)
signal inventory_changed(items: Array, notes: Array)                      # inventory -> ui
signal stage_changed(stage: String, prev: String)                         # puzzles -> ui, audio
signal entity_state(state: String, prev: String)                          # entity -> audio, lighting, ui
signal entity_spotted()                                                   # entity -> audio, player (flinch)
signal entity_caught()                                                    # entity (after the jumpscare) -> game
signal game_state(state: String, prev: String)                            # game -> all
signal game_win()                                                         # puzzles -> game
signal settings_changed(key: String, value: Variant)                      # settings -> renderer/audio/input/ui
signal ui_start()                                                         # ui menu "Nouvelle partie" -> game
