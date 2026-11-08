// STUB — to be replaced by the gameplay module (see ARCHITECTURE.md §Puzzles / scenario).
// Owns the whole scenario: objectives, notes, code generation, registering every interactable,
// scripted events (light blowout, rocking chair, first visit), hiding interaction, win condition.
// Public API (must be kept):
//   constructor(game); async init(); start(); update(dt); reset(kind)
//   .stage   current scenario stage id (string)
//   .code    4-digit string (digits 1..9), random per new game
//   .found   { duck, horse, clock, tv } -> digit string or null
//   debugGoto(stage)   jump to a stage (debug)
export class Puzzles {
  constructor(game) { this.game = game; this.stage = 'intro'; this.code = '0000'; this.found = { duck: null, horse: null, clock: null, tv: null }; }
  async init() {}
  start() { this.game.ui.setObjective?.('Explore le sous-sol.'); }
  update() {}
  reset() {}
  debugGoto() {}
}
