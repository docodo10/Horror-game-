import * as THREE from 'three';
import * as L from '../config/layout.js';

// Puzzles (gameplay module) — owns the whole scenario: objectives, notes, code generation, every interactable,
// scripted beats (light blowout, rocking chair, first visit after the breaker, aggression after the key),
// ambient scares, hints, hiding, win condition. See ARCHITECTURE.md §5.
// Public API:
//   constructor(game); async init(); start(); update(dt); reset(kind)
//   .stage   'intro' | 'dark' | 'power' | 'code' | 'escape' | 'win'
//   .code    4-digit string (digits 1..9), random per new game (debug: ?debug&code=1234)
//   .found   { duck, horse, clock, tv } -> digit string or null
//   debugGoto(stage) -> Promise   jump to a stage (debug; also ?stage=dark|power|code|escape|win in the URL)
//   additions: .flags (progress flags), objective() -> current objective text, tension() -> 0..1
// Emits: 'puzzles:stage' { stage, prev }, 'noise' (loudness table), 'game:win'.

export const STAGES = ['intro', 'dark', 'power', 'code', 'escape', 'win'];
const CLUES = ['duck', 'horse', 'clock', 'tv'];

const NBSP = ' ';
/** French typography: non-breaking space before ! ? : ; » and after «. */
const fr = (s) => (typeof s === 'string' ? s.replace(/ ([!?:;»])/g, `${NBSP}$1`).replace(/« /g, `«${NBSP}`) : s);
const rand = (a, b) => a + Math.random() * (b - a);
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const ease = (k) => k * k * (3 - 2 * k);
const lerp = (a, b, t) => a + (b - a) * t;

const NOTES = {
  note1: {
    title: 'Note pliée', style: 'note',
    text: 'Reste en bas. Pas un bruit.\nElle a le sommeil léger…\n\nLa clé de la porte d’en haut est dans le coffret de Léa.\n\n— M.',
  },
  note2: {
    title: 'Dessin d’enfant', style: 'child',
    text: 'MA GARDIENNE\n\nElle chante quand elle te cherche.\nSi tu l’entends, cours dans le placard sous l’escalier.\nElle regarde jamais dedans…\nsauf si elle te voit y aller.\n\nLéa, 7 ans',
  },
  note3: {
    title: 'Coupure de journal', style: 'newspaper',
    text: 'LE COURRIER DU LAC — 14 novembre 1994\n\nDEUX ENFANTS RETROUVÉS DANS UN SOUS-SOL\n\n'
      + 'Léa, 7 ans, et son frère Mathis, 10 ans, ont été retrouvés hier, enfermés depuis trois jours dans le sous-sol '
      + 'de la maison familiale. Leur gardienne, une femme de 61 ans, reste introuvable.\n\n'
      + '« Elle disait qu’elle nous protégeait de dehors. Elle chantait toute la nuit, en haut », a raconté la fillette.\n\n'
      + 'La maison est inhabitée depuis.',
  },
  box: {
    title: 'Le coffret de Léa', style: 'child',
    text: 'MON COFFRET SECRET\nTOUCHE PAS !!\n\nLe code, dans l’ordre :\n1. le canard\n2. le cheval\n3. l’horloge\n4. la télé\n\n(chaque chose cache un chiffre)\n\nLéa',
  },
};

const CLUE_HINTS = {
  duck: 'Le canard en plastique, près du coin des enfants… Et en dessous ?',
  horse: 'Le petit cheval, sur l’étagère… Peut-être sous son socle.',
  clock: 'La grande horloge est arrêtée. Sur quelle heure ?',
  tv: 'La télé… Il faut du courant. Mais elle va faire du bruit.',
};

// Ambient random scares (real recorded samples). minT = tension needed before it can play, w = weight.
const SCARES = [
  { name: 'house_creak', minT: 0, w: 3, vol: 0.85 },
  { name: 'stair_creak', minT: 0.1, w: 2, vol: 0.8 },
  { name: 'ceiling_walk', minT: 0.2, w: 2, vol: 0.9 },
  { name: 'knock_wall', minT: 0.4, w: 1.4, vol: 0.75 },
  { name: 'ceiling_steps', minT: 0.45, w: 1.2, vol: 0.8 },
  { name: 'window_tap', minT: 0.55, w: 0.6, vol: 0.6 },
  { name: 'whisper', minT: 0.6, w: 0.8, vol: 0.55, sub: '(Un chuchotement, tout près…)' },
  { name: 'giggle', minT: 0.7, w: 0.6, vol: 0.5, sub: '(Un rire d’enfant…)' },
];
const STAGE_TENSION = { intro: 0, dark: 0.2, power: 0.35, code: 0.55, escape: 0.85, win: 0 };

export class Puzzles {
  constructor(game) {
    this.game = game;
    this.stage = 'intro';
    this.code = '0000';
    this.found = { duck: null, horse: null, clock: null, tv: null };
    this.flags = {
      note1: false, blackout: false, flashlight: false, breaker: false, summoned: false, summonDone: false,
      boxNote: false, boxOpen: false, key: false, doorUnlocked: false, doorOpened: false, won: false,
      rocked: false, gnomeMoved: false,
    };
    this.stageTime = 0;
    this.stats = { codeAttempts: 0, rattles: 0 };

    this._started = false;
    this._waits = [];
    this._tweens = [];
    this._gen = 0;
    this._taken = {};
    this._seen = {};
    this._objText = null;
    this._idle = 0;
    this._hintN = 0;
    this._flickT = rand(5, 9);
    this._tvNoiseT = 0;
    this._tvLook = 0;
    this._lookT = 0;
    this._scareT = 40;
    this._lastScare = null;
    this._summon = { t: 0, sawActive: false };
    this._winT = Infinity;
    this._blowoutPending = false;
    this._proxies = [];

    this._camPos = new THREE.Vector3();
    this._camDir = new THREE.Vector3();
    this._tmp = new THREE.Vector3();
    this._rockPos = new THREE.Vector3(L.PROPS.rockingChair.pos[0], 0.7, L.PROPS.rockingChair.pos[2]);
  }

  // =================================================================== lifecycle

  async init() {
    const g = this.game;
    this.interaction = g.interaction;
    this.code = this._makeCode();
    const d = this._digits();
    try { g.world.setClueDigits?.(d); } catch (e) { console.warn('[puzzles] setClueDigits', e); }
    try { g.world.tv?.setDigit?.(d.tv); } catch (e) { console.warn('[puzzles] tv.setDigit', e); }

    this._registerAll();

    g.events.on('power', ({ on }) => {
      const tv = g.world.tv;
      if (!on && tv?.isOn) { try { tv.setOn(false); } catch (e) { /* ignore */ } }
    });
    g.events.on('player:hide', ({ hidden }) => {
      if (hidden && this.flags.summoned && !this.flags.summonDone && !this._seen.hideTip) {
        this._seen.hideTip = true;
        this._say('Ne bouge plus. Ne fais pas un bruit…', 3.5);
      }
    });
    if (g.debug) console.log('[puzzles] code', this.code, 'interactables', this.interaction.entries.size);
  }

  start() {
    if (this._started) return;
    this._started = true;
    const g = this.game, ui = g.ui;
    ui.setNight?.(g.night, g.nightsTotal);
    ui.setClues?.({ ...this.found });
    if (g.world.power === false) this.flags.blackout = true; // ?power=off
    this._advance();
    this._setObjective(this._objectiveText(), true);

    const dbg = this._debugStageParam();
    if (dbg) { this._script(() => this.debugGoto(dbg)); return; }

    this._script(async () => {
      await ui.fadeTo?.(1, 0);
      await ui.fadeTo?.(0, 3);
    });
    this._script(async () => {
      await this._wait(1.6);
      if (this.stage === 'intro') this._say('…Où suis-je ?', 3.5);
    });
  }

  update(dt) {
    if (!this._started || this.game.state !== 'playing') return;
    this._tickWaits(dt);
    this._tickTweens(dt);
    if (this.flags.won) return;
    const g = this.game;
    const modal = !!g.ui?.isModalOpen?.();
    if (!modal) { this.stageTime += dt; this._idle += dt; }
    const f = this.flags;

    // ---- intro: flickering ceiling light, automatic blowout after 45 s
    if (this.stage === 'intro' && !f.blackout) {
      if (g.world.power) {
        this._flickT -= dt;
        if (this._flickT <= 0) {
          this._flickT = rand(6, 14);
          try { g.world.lighting?.flicker?.(rand(0.3, 0.7), rand(0.5, 1)); } catch (e) { /* optional */ }
        }
      }
      if (this.stageTime > 45 && !this._blowoutPending && !modal) this._script(() => this._blowoutSequence(0));
    }

    // ---- first visit after the breaker: wait until she has gone back upstairs
    if (f.summoned && !f.summonDone) {
      const ent = g.entity, s = this._summon;
      s.t += dt;
      if (ent?.active) s.sawActive = true;
      const disabled = !ent || ent.state === 'disabled';
      if ((s.sawActive && !ent.active) || (!s.sawActive && s.t > (disabled ? 3 : 12)) || s.t > 180) {
        f.summonDone = true;
        this._progress();
        this._say(s.sawActive ? 'Elle est remontée… Vite, le coffret de Léa.' : 'Elle ne descend pas… Vite, le coffret de Léa.', 4);
        this._advance();
      }
    }

    // ---- TV: loud while on (noise 0.55 every 0.5 s) + digit discovery when looked at
    const tv = g.world.tv;
    if (tv?.isOn) {
      this._tvNoiseT -= dt;
      if (this._tvNoiseT <= 0) {
        this._tvNoiseT = 0.5;
        this._noise(tv.screenPosition || this._objPos(tv.object), 0.55, 'tv');
      }
      if (!this.found.tv && !modal) {
        if (this._looksAt(tv.screenPosition || this._objPos(tv.object), 0.9, 5, false)) this._tvLook += dt; else this._tvLook = Math.max(0, this._tvLook - dt);
        if (this._tvLook > 0.9) {
          this._findClue('tv', `Un chiffre apparaît dans la neige de l’écran : ${this.code[3]}.`);
        }
      }
    } else this._tvLook = 0;

    // ---- rocking chair rocks by itself the first time it is looked at after the blowout
    if (f.blackout && !f.rocked && !modal) {
      this._lookT -= dt;
      if (this._lookT <= 0) {
        this._lookT = 0.2;
        if (this._canSee() && this._looksAt(this._rockPos, 0.88, 6, true)) this._rockBeat();
      }
    }

    // ---- win: walking through the open door (or 1.5 s after it opened)
    if (f.doorOpened) {
      this._winT -= dt;
      if (this._winT <= 0 || this._inHall()) this._win();
    } else if (this._inHall() && (f.key || f.doorUnlocked)) {
      this._win(); // the entity left the door open and the player carries the key
    }

    if (!modal) {
      this._hints();
      this._ambient(dt);
    }
  }

  reset(kind) {
    this._gen++;
    this.interaction?.reset?.();
    // finish running tweens (puts examined objects back in place)
    for (const t of this._tweens.splice(0)) { try { t.fn(1); } catch (e) { /* ignore */ } t.resolve(); }
    const g = this.game, f = this.flags;
    if (kind !== 'caught') return;

    if (f.summoned && !f.summonDone) f.summonDone = true; // she took the player back upstairs: the visit is over
    const tv = g.world.tv;
    if (tv?.isOn) { try { tv.setOn(false); } catch (e) { /* ignore */ } }
    if (f.doorOpened && !f.won) this._winT = Infinity; // must walk through now
    // keep the lights consistent with the progress
    try {
      if (f.breaker && !g.world.power) g.world.setPower(true);
      else if (f.blackout && !f.breaker && g.world.power) g.world.setPower(false);
    } catch (e) { console.warn(e); }

    // the garden gnome "moved" while the player was away
    const gnome = this._find(['extra_gnome']);
    if (gnome) {
      const wp = gnome.getWorldPosition(new THREE.Vector3());
      gnome.rotation.y = Math.atan2(L.SPAWN.x - wp.x, L.SPAWN.z - wp.z) + rand(-0.15, 0.15);
      f.gnomeMoved = true;
    }

    this._idle = 0; this._hintN = 0;
    this._scareT = rand(30, 50);
    this._advance();
    this._setObjective(this._objectiveText(), true);
    g.ui?.setClues?.({ ...this.found });
    g.ui?.setNight?.(g.night, g.nightsTotal);
    g.inventory?._emit?.();
    const night = g.night;
    this._script(async () => {
      await this._wait(1.8);
      this._say(night >= g.nightsTotal ? 'Encore ici… C’est ma dernière chance.' : 'Encore ici… Elle ne me laissera pas partir.', 4);
    });
  }

  // =================================================================== stage machine

  _computeStage() {
    const f = this.flags;
    if (f.won) return 'win';
    if (f.key) return 'escape';
    if (f.breaker && f.summonDone) return 'code';
    if (f.breaker || (f.blackout && f.flashlight)) return 'power';
    if (f.blackout) return 'dark';
    return 'intro';
  }

  _advance() {
    const next = this._computeStage();
    if (STAGES.indexOf(next) > STAGES.indexOf(this.stage)) this._enterStage(next);
    else this._setObjective(this._objectiveText());
  }

  _enterStage(next) {
    const prev = this.stage;
    this.stage = next;
    this.stageTime = 0;
    this._idle = 0; this._hintN = 0;
    if (this.game.debug) console.log(`[puzzles] stage ${prev} -> ${next}`);
    this.game.events.emit('puzzles:stage', { stage: next, prev });
    this._setObjective(this._objectiveText());
    if (next === 'escape') this._escapeBeat();
  }

  objective() { return this._objectiveText(); }

  _objectiveText() {
    const f = this.flags;
    switch (this.stage) {
      case 'intro': return 'Explore le sous-sol.';
      case 'dark': return 'Trouve une lumière.';
      case 'power':
        return f.summoned && !f.summonDone ? 'Cache-toi ! (placard sous l’escalier)' : 'Rétablis le courant (panneau électrique, buanderie).';
      case 'code': {
        if (f.boxOpen) return 'Prends la clé dans le coffret.';
        const n = this._foundCount();
        if (n >= 4) return 'Ouvre le cadenas du coffret.';
        return n ? `Trouve le code du coffret (${n}/4 chiffres)` : 'Trouve le code du coffret (4 chiffres)';
      }
      case 'escape': return 'Monte l’escalier et ouvre la porte.';
      default: return '';
    }
  }

  _setObjective(text, force = false) {
    if (!force && text === this._objText) return;
    this._objText = text;
    try { this.game.ui?.setObjective?.(fr(text)); } catch (e) { console.warn(e); }
  }

  _progress() { this._idle = 0; this._hintN = 0; }

  tension() {
    const base = STAGE_TENSION[this.stage] ?? 0;
    return Math.max(0, Math.min(1, base + 0.12 * ((this.game.night || 1) - 1) + Math.min(0.15, (this.game.time || 0) / 1500)));
  }

  // =================================================================== registration

  _registerAll() {
    const g = this.game, w = g.world, H = w.handles || {};
    const I = this.interaction;
    const drawer = { open: 'Ouvrir le tiroir', close: 'Fermer le tiroir', noise: 0.15 };
    this._regHandle('dresser.drawerTop', drawer);
    this._regHandle('dresser.drawerMid', { ...drawer, empty: 'Des vieux vêtements d’enfant, pliés avec soin.' });
    this._regHandle('dresser.drawerBottom', { ...drawer, empty: 'Des cassettes vidéo sans étiquette.' });
    this._regHandle('endTable.drawer', drawer);
    this._regHandle('alcoveCabinet.drawer_01', drawer);
    this._regHandle('alcoveCabinet.drawer_02', { ...drawer, empty: 'Des élastiques, des bouts de crayons… rien d’utile.' });
    const cab = { open: 'Ouvrir la porte du meuble', close: 'Fermer la porte du meuble', noise: 0.15 };
    this._regHandle('alcoveCabinet.door_01', cab);
    this._regHandle('alcoveCabinet.door_02', { ...cab, empty: 'Des pots de peinture séchée.' });
    this._regHandle('powerBox.door', { open: 'Ouvrir le panneau électrique', close: 'Fermer le panneau électrique', noise: 0.15 });

    // ---- breaker lever
    const lever = H['powerBox.lever'];
    if (lever?.object) {
      I.register({
        id: 'powerBox.lever', object: lever.object, prompt: 'Abaisser le levier',
        enabled: () => !this.flags.breaker && !w.power && (H['powerBox.door'] ? H['powerBox.door'].isOpen !== false : true),
        onInteract: () => this._flipBreaker(),
      });
    }

    // ---- locked box: label (child's code note) + padlock keypad
    const lid = H['lockedBox.lid'], lock = H['lockedBox.lock'];
    if (lid?.object) {
      I.register({
        id: 'lockedBox', object: lid.object,
        prompt: () => (!this.flags.boxOpen ? 'Examiner le coffret' : (lid.isOpen ? null : 'Ouvrir le coffret')),
        onInteract: async () => {
          if (!this.flags.boxOpen) return this._readNote('box', NOTES.box, lid, () => { this.flags.boxNote = true; this._progress(); });
          this._noise(this._hpos(lid), 0.2, 'box');
          await lid.open?.();
        },
      });
    }
    if (lock?.object) {
      I.register({
        id: 'lockedBox.lock', object: lock.object, prompt: 'Entrer le code',
        enabled: () => !this.flags.boxOpen,
        onInteract: () => this._keypad(),
      });
    }

    // ---- pickups
    this._regItem('flashlight', 'Prendre la lampe de poche', 'dresser.drawerTop');
    this._regItem('battery1', 'Prendre la pile', 'endTable.drawer');
    this._regItem('battery2', 'Prendre la pile', 'alcoveCabinet.drawer_01');
    this._regItem('key', 'Prendre la clé', 'lockedBox.lid', () => this.flags.boxOpen);

    // ---- notes
    this._regNote('note1', () => (this.flags.note1 ? 'Relire la note' : 'Lire la note'), NOTES.note1, null, () => {
      if (!this.flags.note1) {
        this.flags.note1 = true;
        this._progress();
        if (!this.flags.blackout) this._script(() => this._blowoutSequence(1.4));
      }
    });
    this._regNote('note2', 'Regarder le dessin', NOTES.note2, null);
    this._regNote('note3', 'Lire la coupure de journal', NOTES.note3, 'alcoveCabinet.door_01');

    // ---- clues
    const C = w.clues || {};
    this._regClue('duck', C.duck, 'Examiner le canard', true,
      (d) => `Sous le canard, quelqu’un a écrit un chiffre au feutre : ${d}.`);
    this._regClue('horse', C.horse, 'Examiner le cheval', true,
      (d) => `Un chiffre est gravé sous le socle du cheval : ${d}.`);
    this._regClue('clock', C.clock, 'Examiner l’horloge', false,
      (d) => `L’horloge est arrêtée sur ${d} h pile. La petite aiguille pointe le ${d}.`);

    // ---- TV (needs power, loud while on)
    const tv = w.tv;
    if (tv?.object) {
      const tvEntry = {
        prompt: () => (tv.isOn ? 'Éteindre la télé' : 'Allumer la télé'),
        onInteract: () => this._toggleTV(),
      };
      I.register({ id: 'tv', object: tv.object, ...tvEntry });
      if (C.tv && C.tv !== tv.object && !this._isDescendant(C.tv, tv.object)) I.register({ id: 'tv.screen', object: C.tv, ...tvEntry });
    }

    // ---- upstairs door
    const door = H['door.upstairs'];
    if (door?.object) {
      const hasKey = () => this.flags.key || !!g.inventory?.has?.('key');
      I.register({
        id: 'door.upstairs', object: door.object, maxDistance: 2.4,
        prompt: () => {
          if (this.flags.won || this.flags.doorOpened) return null;
          if (door.isOpen) return hasKey() ? 'Passer la porte' : null;
          if (door.locked) return hasKey() ? 'Déverrouiller (maintenir)' : 'Ouvrir la porte';
          return 'Ouvrir la porte';
        },
        hold: () => (!door.isOpen && door.locked && hasKey() ? 2 : 0),
        holdPrompt: 'Déverrouillage…',
        onHoldStart: () => {
          const p = this._hpos(door);
          this._noise(p, 0.35, 'door.unlock');
          this._sfx('key_pickup', p, 0.7);
        },
        onInteract: async () => {
          if (door.isOpen || !door.locked) return this._openDoorAndWin();
          if (hasKey()) return this._unlockDoor();
          return this._rattle();
        },
      });
    }

    // ---- closet (hiding spot)
    // NB: `{ id:'closet', door, ...CLOSET }` lets the layout's CLOSET.door config overwrite the handle: fix it up
    // (without mutating world data) so player.enterHide always receives a spot whose .door is the real Handle.
    let spot = (w.hideSpots || []).find((s) => s.id === 'closet') || (w.hideSpots || [])[0] || null;
    const isHandle = (d) => !!(d && d.object && (d.open || d.toggle));
    if (!spot && H['door.closet']) spot = { ...L.CLOSET, id: 'closet', door: H['door.closet'] };
    else if (spot && !isHandle(spot.door) && isHandle(H['door.closet'])) spot = { ...spot, door: H['door.closet'], doorLayout: spot.door };
    const cdoor = isHandle(spot?.door) ? spot.door : H['door.closet'];
    if (spot && cdoor?.object) {
      I.register({
        id: 'closet.hide', object: cdoor.object, prompt: 'Se cacher', maxDistance: 2.3,
        enabled: () => !g.player?.hidden,
        onInteract: () => this._enterCloset(spot),
      });
      I.register({
        id: 'closet.exit', object: cdoor.object, prompt: 'Sortir du placard', whenHidden: true,
        enabled: () => !!g.player?.hidden,
        onInteract: () => this._exitCloset(spot),
      });
    }

    // ---- window (proxy box over the opening)
    const W = L.WINDOW;
    const win = this._proxy('window', [W.maxX - W.minX, W.maxY - W.minY, 0.06], [(W.minX + W.maxX) / 2, (W.minY + W.maxY) / 2, W.z - 0.04]);
    const winLines = ['Trop petite… et il y a des barreaux.', 'Il neige, dehors. Personne ne viendra me chercher.', 'Les barreaux sont scellés dans le béton.'];
    I.register({
      id: 'window', object: win, prompt: 'Examiner la fenêtre', maxDistance: 2.8,
      onInteract: async () => {
        const p = win.getWorldPosition(new THREE.Vector3());
        this._sfx('window_tap', p, 0.8);
        this._noise(p, 0.1, 'window');
        this._say(this._cycle('window', winLines), 3.5);
        await this._wait(0.6);
      },
    });

    this._registerFlavour();
  }

  /** Atmosphere-only interactables (base props + batch-2 extras found by scene name). */
  _registerFlavour() {
    const g = this.game, I = this.interaction, f = this.flags;
    const canSee = () => this._canSee();
    const look = (id, names, prompt, lines, opts = {}) => {
      const obj = Array.isArray(names) ? this._find(names) : names;
      if (!obj) return;
      I.register({
        id, object: obj, prompt, maxDistance: opts.maxDistance || 2.1,
        onInteract: async () => {
          if (opts.light !== false && !canSee()) { this._say('Il fait trop noir pour voir.', 2.5); return; }
          const p = obj.getWorldPosition(new THREE.Vector3());
          if (opts.sfx) this._sfx(opts.sfx, p, opts.vol ?? 0.7);
          if (opts.noise) this._noise(p, opts.noise, id);
          const text = typeof lines === 'function' ? lines() : this._cycle(id, lines);
          if (text) this._say(text, Math.max(3, text.length * 0.055));
          await opts.after?.(p);
          await this._wait(0.4);
        },
      });
    };

    // base props (scene names = layout.PROPS keys, model ids as fallback)
    look('look.photo', ['photoFrame', 'standing_picture_frame_01'], 'Regarder la photo',
      ['Une très grande femme, derrière deux enfants. Elle ne regarde pas l’objectif.']);
    look('look.alarm', ['alarmClock', 'alarm_clock_01'], 'Examiner le réveil',
      ['3 h 33. Le tic-tac est beaucoup trop fort.', 'Il avance toujours. Pas l’horloge.']);
    look('look.cassette', ['cassette', 'portable_cassette_player'], 'Examiner le baladeur',
      ['Une cassette étiquetée au crayon : « BERCEUSES — NE PAS ÉCOUTER ».']);
    const rock = this._find(['rockingChair', 'Rockingchair_01']);
    if (rock) { rock.getWorldPosition(this._rockPos); this._rockPos.y += 0.6; }
    look('look.rocking', rock, 'Examiner la chaise berçante',
      () => (f.rocked ? 'Elle s’est balancée toute seule… Je l’ai vue bouger.' : 'Une vieille chaise berçante. Le coussin est encore creusé.'));

    // pull-chain socket / dead bulb in the nook (proxy so it works whatever the node names are)
    const b = L.PROPS.bulb.pos;
    const bulb = this._proxy('bulb', [0.3, 0.42, 0.3], [b[0], b[1] + 0.02, b[2]]);
    look('look.bulb', bulb, 'Tirer la chaînette', ['Clic. Rien. L’ampoule est grillée.', 'Clic… Clic. Toujours rien.'],
      { light: false, sfx: 'flashlight_click', vol: 0.9, maxDistance: 2.3 });

    // batch-2 extras (layout.EXTRA_PROPS, scene names 'extra_<key>'; optional)
    look('look.gnome', ['extra_gnome'], 'Examiner le nain de jardin',
      () => (f.gnomeMoved ? 'Il… n’était pas tourné comme ça, avant.' : 'Il me fixe…'));
    look('look.mirror', ['extra_mirror'], 'Se regarder dans le miroir',
      ['Je ne me reconnais presque pas.', 'Mes yeux… J’ai l’air de ne pas avoir dormi depuis des jours.'],
      { after: () => this._mirrorScare() });
    look('look.oldTv', ['extra_oldTv'], 'Examiner la vieille télé',
      () => (g.world.power ? 'Elle grésille… Elle n’est même pas branchée.' : 'Une vieille télé. Le fil a été coupé.'));
    look('look.boombox', ['extra_boombox'], 'Allumer la radio', ['Rien. Les piles sont mortes.'],
      { light: false, sfx: 'flashlight_click', vol: 0.8 });
    look('look.toolbox', ['extra_toolbox'], 'Fouiller le coffre à outils',
      ['Des vis rouillées… Rien pour forcer une serrure.'], { sfx: 'cloth_move', noise: 0.06 });
    look('look.laundry', ['extra_laundry'], 'Fouiller le panier',
      ['Des vêtements d’enfant. Ils sont encore humides…'], { light: false, sfx: 'cloth_move', vol: 0.8 });
    look('look.bat', ['extra_bat'], 'Prendre le bâton', ['Non… Elle est bien trop grande pour ça.'], { light: false });
    look('look.football', ['extra_football'], 'Examiner le ballon', ['Un ballon tout dégonflé. Il y a des marques de dents.']);
    look('look.gamepad', ['extra_gamepad'], 'Examiner la manette', ['Une vieille manette. Le fil a été coupé net.']);
    look('look.mousetrap', ['extra_mousetrap'], 'Examiner la souricière', ['Une souricière. Il y a encore quelque chose dedans…']);
    look('look.photoA', ['extra_stairPhotoA'], 'Regarder la photo', ['Une photo de famille. Le visage de la femme a été gratté.']);
    look('look.photoB', ['extra_stairPhotoB'], 'Regarder la photo', ['Deux enfants devant la maison, en hiver. Personne ne sourit.']);
  }

  _regHandle(id, cfg) {
    const h = this.game.world.handles?.[id];
    if (!h?.object) return;
    this.interaction.register({
      id, object: h.object,
      prompt: () => (h.isOpen ? cfg.close : cfg.open),
      onInteract: async () => {
        const opening = !h.isOpen;
        this._noise(this._hpos(h), cfg.noise, id);
        if (opening) await (h.open ? h.open() : h.toggle?.());
        else await (h.close ? h.close() : h.toggle?.());
        if (opening && cfg.empty && !this._seen['empty.' + id]) {
          this._seen['empty.' + id] = true;
          this._say(cfg.empty, 3);
        }
      },
    });
  }

  _regItem(itemId, prompt, insideHandle, extraEnabled) {
    const obj = this.game.world.items?.[itemId];
    if (!obj) return;
    const h = insideHandle ? this.game.world.handles?.[insideHandle] : null;
    this.interaction.register({
      id: 'item.' + itemId, object: obj, prompt,
      enabled: () => !this._taken[itemId] && obj.visible !== false && (!h || h.isOpen !== false) && (!extraEnabled || extraEnabled()),
      onInteract: () => this._takeItem(itemId),
    });
  }

  _regNote(itemId, prompt, note, insideHandle, onRead) {
    const obj = this.game.world.items?.[itemId];
    if (!obj) return;
    const h = insideHandle ? this.game.world.handles?.[insideHandle] : null;
    this.interaction.register({
      id: itemId, object: obj, prompt,
      enabled: () => obj.visible !== false && (!h || h.isOpen !== false),
      onInteract: () => this._readNote(itemId, note, obj, onRead),
    });
  }

  _regClue(key, obj, prompt, tilt, textFn) {
    if (!obj) return;
    this.interaction.register({
      id: 'clue.' + key, object: obj, prompt,
      onInteract: async () => {
        if (!this._canSee()) { this._say('Il fait trop noir pour voir.', 2.5); return; }
        const i = CLUES.indexOf(key);
        const d = this.code[i];
        const known = !!this.found[key];
        const p = obj.getWorldPosition(new THREE.Vector3());
        if (tilt) {
          this._sfx('pickup', p, 0.45);
          await this._tiltReveal(obj, () => (known ? this._say(textFn(d), 3.5) : this._findClue(key, textFn(d))));
        } else {
          if (known) this._say(textFn(d), 3.5); else this._findClue(key, textFn(d));
          if (key === 'clock' && !this._seen.chime && this.game.world.power) {
            this._seen.chime = true;
            this._script(async () => {
              await this._wait(2.2);
              this._sfx('clock_chime', p, 0.55);
              await this._wait(1.2);
              this._say('Elle sonne… alors qu’elle est arrêtée ?', 3);
            });
          }
          await this._wait(0.5);
        }
      },
    });
  }

  // =================================================================== actions

  _canSee() {
    const w = this.game.world, fl = this.game.player?.flashlight;
    return !!w.power || !!(fl && fl.has && fl.on && (fl.battery ?? 1) > 0);
  }

  async _readNote(id, note, obj, onRead) {
    if (!this._canSee()) { this._say('Il fait trop noir pour lire.', 2.5); return; }
    const g = this.game;
    const p = obj?.getWorldPosition ? obj.getWorldPosition(new THREE.Vector3()) : this._hpos(obj);
    this._sfx('paper', p, 0.8);
    g.inventory?.addNote?.({ id, ...note });
    await g.modal(() => g.ui.showNote({ title: fr(note.title), text: fr(note.text), style: note.style }));
    this._sfx('paper', p, 0.5);
    onRead?.();
  }

  _takeItem(itemId, { quiet = false } = {}) {
    if (this._taken[itemId]) return;
    this._taken[itemId] = true;
    const g = this.game, obj = g.world.items?.[itemId];
    const pos = obj ? obj.getWorldPosition(new THREE.Vector3()) : g.camera.getWorldPosition(new THREE.Vector3());
    if (obj) obj.visible = false;
    this.interaction.unregister('item.' + itemId);
    const touch = !!g.input?.isTouch;
    switch (itemId) {
      case 'flashlight': {
        g.inventory.add('flashlight');
        this.flags.flashlight = true;
        try {
          g.player?.giveFlashlight?.();
          if (g.player?.flashlight && !g.player.flashlight.on) g.player.setFlashlightOn?.(true);
        } catch (e) { console.warn(e); }
        if (!quiet) {
          this._sfx('pickup', pos, 0.9);
          this._say(touch ? 'Une lampe de poche ! (bouton lampe pour l’éteindre)' : 'Une lampe de poche ! (F pour l’allumer ou l’éteindre)', 4, { critical: true });
        }
        break;
      }
      case 'battery1':
      case 'battery2':
        g.inventory.add('battery');
        if (!quiet) { this._sfx('pickup', pos, 0.8); this._say('Une pile de rechange. La lampe en aura besoin.', 3); }
        break;
      case 'key':
        g.inventory.add('key');
        this.flags.key = true;
        if (!quiet) { this._sfx('key_pickup', pos, 1); this._say('La clé ! Maintenant, la porte d’en haut.', 3.5); }
        break;
      default: g.inventory.add(itemId);
    }
    this._progress();
    this._advance();
  }

  _findClue(key, text) {
    if (this.found[key]) return;
    this.found[key] = this.code[CLUES.indexOf(key)];
    this.game.ui?.setClues?.({ ...this.found });
    this._progress();
    this._say(text, 4);
    if (this._foundCount() === 4 && !this.flags.boxOpen) {
      this._script(async () => {
        await this._wait(4.2);
        if (!this.flags.boxOpen) this._say(`J’ai les quatre chiffres : ${this._codeFromFound()}. Le cadenas du coffret, maintenant.`, 4.5);
      });
    }
    this._setObjective(this._objectiveText());
  }

  _foundCount() { let n = 0; for (const k of CLUES) if (this.found[k]) n++; return n; }

  _codeFromFound() { return CLUES.map((k) => this.found[k] || '?').join(' '); }

  async _blowoutSequence(delay) {
    if (this.flags.blackout || this._blowoutPending) return;
    this._blowoutPending = true;
    if (delay > 0) await this._wait(delay);
    if (this.flags.blackout) { this._blowoutPending = false; return; }
    try { this.game.world.lighting?.flicker?.(0.9, 1); } catch (e) { /* optional */ }
    await this._wait(1.1);
    this._doBlackout();
  }

  _doBlackout({ quiet = false } = {}) {
    this._blowoutPending = false;
    if (this.flags.blackout) return;
    this.flags.blackout = true;
    const g = this.game, w = g.world;
    try {
      if (w.lighting?.blowout) w.lighting.blowout(); else w.setPower(false);
      if (w.power) w.setPower(false);
      const lever = w.handles?.['powerBox.lever'];
      if (lever?.isOn) Promise.resolve(lever.setOn?.(false)).catch((e) => console.warn(e)); // the breaker tripped
    } catch (e) { console.warn('[puzzles] blowout', e); }
    this._progress();
    if (!quiet) {
      this._script(async () => {
        await this._wait(0.35);
        this._sfx('player_gasp', null, 0.8);
        await this._wait(0.9);
        this._say('Non, non, non… Il fait tout noir.', 3.5);
      });
    }
    this._advance();
  }

  _rockBeat() {
    this.flags.rocked = true;
    const props = this.game.world.props;
    try {
      if (props?.rockChair) props.rockChair(6);
      else this._sfx('rocking_chair', this._rockPos, 0.8);
    } catch (e) { console.warn(e); }
    this._script(async () => { await this._wait(0.5); this._sfx('heartbeat_single', null, 0.8); });
  }

  async _flipBreaker() {
    if (this.flags.breaker) return;
    const g = this.game, w = g.world;
    const lever = w.handles?.['powerBox.lever'];
    const pos = this._panelPos();
    this.flags.breaker = true;
    this._noise(pos, 1.0, 'breaker');
    try { await lever?.setOn?.(true); } catch (e) { console.warn(e); }
    if (!w.power) w.setPower(true);
    this.flags.summoned = true;
    this._summon = { t: 0, sawActive: false };
    try { g.entity?.summon?.(pos.clone(), { reason: 'breaker' }); } catch (e) { console.warn('[puzzles] summon', e); }
    this._progress();
    this._advance();
    this._script(async () => {
      await this._wait(0.9);
      g.ui?.alert?.(fr('CACHE-TOI !'), 2.5);
      this._setObjective(this._objectiveText());
      await this._wait(2.0);
      if (!this.flags.summonDone) this._say('Le bruit… Elle l’a entendu. Le placard sous l’escalier !', 4, { critical: true });
    });
    await this._wait(0.4);
  }

  async _toggleTV() {
    const g = this.game, tv = g.world.tv;
    if (!tv) return;
    const p = tv.screenPosition ? tv.screenPosition.clone() : this._objPos(tv.object);
    if (!tv.isOn) {
      if (!g.world.power) {
        this._sfx('flashlight_click', p, 0.6);
        this._say('Rien. Pas de courant.', 2.5);
        await this._wait(0.4);
        return;
      }
      tv.setOn(true);
      this._sfx('tv_on', p, 0.9);
      this._tvNoiseT = 0; this._tvLook = 0;
      if (!this._seen.tvLoud) { this._seen.tvLoud = true; this._say('Ça fait tellement de bruit…', 3); }
    } else {
      tv.setOn(false);
      this._sfx('tv_off', p, 0.9);
    }
    await this._wait(0.5);
  }

  async _keypad() {
    if (this.flags.boxOpen) return;
    const g = this.game;
    const lock = g.world.handles?.['lockedBox.lock'];
    const p = this._hpos(lock);
    const r = await g.modal(() => g.ui.showKeypad({ title: fr('Cadenas du coffret'), length: 4 }));
    if (r == null) return;
    const s = String(r).replace(/\D/g, '');
    this.stats.codeAttempts++;
    if (s === this.code) { await this._openBox(); return; }
    this._sfx('lock_fail', p, 0.9);
    this._noise(p, 0.15, 'lock');
    this._say(this._foundCount() < 4 ? 'Ça ne marche pas. Il me manque des chiffres…' : 'Ça ne marche pas… L’ordre : canard, cheval, horloge, télé.', 3.5);
    await this._wait(0.4);
  }

  async _openBox() {
    if (this.flags.boxOpen) return;
    const g = this.game, H = g.world.handles || {};
    this.flags.boxOpen = true;
    CLUES.forEach((k, i) => { if (!this.found[k]) this.found[k] = this.code[i]; });
    g.ui?.setClues?.({ ...this.found });
    const p = this._hpos(H['lockedBox.lock'] || H['lockedBox.lid']);
    this._sfx('lock_success', p, 1);
    try { await H['lockedBox.lock']?.open?.(); } catch (e) { console.warn(e); }
    this._noise(p, 0.2, 'box');
    try { await H['lockedBox.lid']?.open?.(); } catch (e) { console.warn(e); }
    this._progress();
    this._say('Ça s’ouvre ! La clé est dedans.', 3);
    this._advance();
  }

  _escapeBeat() {
    const g = this.game;
    try { g.entity?.setAggression?.(2); } catch (e) { console.warn(e); }
    this._script(async () => {
      await this._wait(0.9);
      this._sfx('ceiling_walk', new THREE.Vector3(-3.0, 3.0, -3.8), 1);
      await this._wait(1.6);
      this._say('Elle bouge, là-haut… Elle sait.', 3.5);
      await this._wait(2.5);
      this._sfx('house_creak', new THREE.Vector3(-3.0, 3.6, -3.4), 0.9);
    });
  }

  async _rattle() {
    const door = this.game.world.handles?.['door.upstairs'];
    const p = this._hpos(door);
    this.stats.rattles++;
    this._sfx('door_locked', p, 1);
    this._noise(p, 0.35, 'door.rattle');
    this._say(this.stats.rattles === 1 ? 'Verrouillée.' : 'Verrouillée. Il me faut la clé… et pas de bruit.', 2.5);
    await this._wait(0.8);
  }

  async _unlockDoor() {
    const door = this.game.world.handles?.['door.upstairs'];
    if (!door || this.flags.doorUnlocked) return;
    const p = this._hpos(door);
    this.flags.doorUnlocked = true;
    door.locked = false;
    this._sfx('unlock', p, 1);
    this._progress();
    await this._wait(0.4);
    await this._openDoorAndWin();
  }

  async _openDoorAndWin() {
    if (this.flags.doorOpened || this.flags.won) return;
    const g = this.game, door = g.world.handles?.['door.upstairs'];
    const p = this._hpos(door);
    this.flags.doorOpened = true;
    if (door) door.locked = false;
    this._sfx('win_door', p, 1);
    this._say('De la lumière… Je sors d’ici !', 3);
    try { if (door && !door.isOpen) await door.open?.(); } catch (e) { console.warn(e); }
    this._winT = 1.5;
  }

  _inHall() {
    const pp = this.game.player?.position;
    if (!pp) return false;
    const H = L.UPPER_HALL;
    return pp.y > 2.0 && pp.x >= H.minX && pp.x <= H.maxX && pp.z < L.ROOM.minZ - 0.12 && pp.z >= H.minZ - 0.5;
  }

  _win() {
    if (this.flags.won) return;
    this.flags.won = true;
    this._winT = Infinity;
    this._advance();
    this.interaction?.reset?.();
    this.game.events.emit('game:win', { time: this.game.time, nights: this.game.night });
  }

  async _enterCloset(spot) {
    const g = this.game, p = g.player;
    if (!p || p.hidden) return;
    const pos = this._hpos(spot.door);
    this._sfx('closet_enter', pos, 0.9);
    this._noise(pos, 0.12, 'closet');
    await Promise.all([Promise.resolve(p.enterHide?.(spot)), this._wait(0.7)]);
  }

  async _exitCloset(spot) {
    const g = this.game, p = g.player;
    if (!p || !p.hidden) return;
    const pos = this._hpos(spot.door);
    this._sfx('closet_exit', pos, 0.9);
    this._noise(pos, 0.12, 'closet');
    await Promise.all([Promise.resolve(p.exitHide?.()), this._wait(0.7)]);
  }

  _mirrorScare() {
    if (this._seen.mirrorScare || STAGES.indexOf(this.stage) < STAGES.indexOf('code') || Math.random() > 0.5) return;
    this._seen.mirrorScare = true;
    const cam = this.game.camera;
    cam.getWorldPosition(this._camPos); cam.getWorldDirection(this._camDir);
    const behind = this._camPos.clone().addScaledVector(this._camDir.setY(0).normalize(), -1.1);
    this._script(async () => {
      await this._wait(1.4);
      this._sfx('whisper', behind, 0.7);
      await this._wait(0.8);
      this._say('…Derrière moi ?', 2.5);
    });
  }

  // =================================================================== hints & ambience

  _hintPlan() {
    const f = this.flags;
    switch (this.stage) {
      case 'intro': return { first: 25, every: 60, text: () => (!f.note1 ? 'Il y a un papier sur la table basse…' : null) };
      case 'dark': return { first: 40, every: 50, text: (n) => (n === 0 ? 'La commode… il y avait une lampe de poche.' : 'Le tiroir du haut de la commode, sous la petite télé.') };
      case 'power':
        if (f.summoned && !f.summonDone) return { first: 14, every: 25, text: () => (this.game.player?.hidden ? null : 'Le placard sous l’escalier… vite !') };
        return {
          first: 50, every: 55,
          text: (n) => (n === 0 ? 'Le panneau électrique doit être dans la buanderie.' : 'Au fond de la buanderie, sur le mur : ouvre le panneau et abaisse le levier.'),
        };
      case 'code': return {
        first: 45, every: 50,
        text: (n) => {
          if (f.boxOpen) return 'La clé, dans le coffret !';
          if (!f.boxNote && n === 0) return 'Le coffret de Léa… sur la console, près des chaises.';
          const missing = CLUES.filter((k) => !this.found[k]);
          if (!missing.length) return `Le cadenas du coffret : ${this._codeFromFound()}.`;
          return CLUE_HINTS[missing[n % missing.length]];
        },
      };
      case 'escape': return {
        first: 40, every: 50,
        text: (n) => (n === 0 ? 'La porte en haut de l’escalier. Vite !' : 'Avec la clé : maintiens le bouton sur la porte pour la déverrouiller.'),
      };
      default: return null;
    }
  }

  _hints() {
    const plan = this._hintPlan();
    if (!plan || this.game.entity?.state === 'chasing') return;
    const at = plan.first + this._hintN * plan.every;
    if (this._idle < at) return;
    const text = plan.text(this._hintN);
    this._hintN++;
    if (text) this._say(text, 4.5, { critical: true, hint: true });
  }

  _ambient(dt) {
    const g = this.game;
    if (g.entity?.active) { this._scareT = Math.max(this._scareT, 8); return; }
    this._scareT -= dt;
    if (this._scareT > 0) return;
    const t = this.tension();
    this._scareT = lerp(75, 24, t) * rand(0.75, 1.35);
    const pool = SCARES.filter((s) => s.minT <= t && s.name !== this._lastScare);
    if (!pool.length) return;
    let sum = 0;
    for (const s of pool) sum += s.w;
    let r = Math.random() * sum, sc = pool[0];
    for (const s of pool) { r -= s.w; if (r <= 0) { sc = s; break; } }
    this._lastScare = sc.name;
    this._sfx(sc.name, this._scarePos(sc.name), sc.vol);
    if (sc.sub) this._say(sc.sub, 2.5);
  }

  _scarePos(name) {
    const V = (x, y, z) => new THREE.Vector3(x, y, z);
    switch (name) {
      case 'house_creak': return pick([V(3.2, 2.3, -2.4), V(-1.5, 2.4, 2.5), V(2.0, 2.2, -4.2), V(-3.3, 2.3, 1.5), V(0.5, 2.45, 0)]);
      case 'stair_creak': { const z = rand(-1.5, 1.4); return V(-3.0, (L.stairHeightAt(-3.0, z) ?? 1) + 0.1, z); }
      case 'ceiling_walk':
      case 'ceiling_steps': return V(rand(-2.2, 3.2), 2.9, rand(-2.5, 2.5));
      case 'knock_wall': return pick([V(3.55, 1.2, -0.8), V(-0.4, 1.3, -2.8), V(-3.2, 0.9, -1.6), V(1.2, 1.0, 2.8)]);
      case 'window_tap': { const W = L.WINDOW; return V((W.minX + W.maxX) / 2, (W.minY + W.maxY) / 2, W.z); }
      case 'whisper': {
        const cam = this.game.camera;
        cam.getWorldPosition(this._camPos); cam.getWorldDirection(this._camDir);
        this._camDir.y = 0;
        if (this._camDir.lengthSq() < 1e-6) this._camDir.set(0, 0, -1);
        this._camDir.normalize();
        return this._camPos.clone().addScaledVector(this._camDir, -1.2).add(V(rand(-0.4, 0.4), 0, rand(-0.4, 0.4)));
      }
      case 'giggle': return pick([V(-2.0, 0.7, 0.3), V(-3.0, 0.8, -1.4), V(-3.0, 3.4, -2.3)]);
      default: return null;
    }
  }

  // =================================================================== debug

  _debugStageParam() {
    let s = this.game.params?.stage;
    if (!s) { try { s = new URLSearchParams(location.search).get('stage'); } catch (e) { s = null; } }
    return s && STAGES.includes(s) && s !== 'intro' ? s : null;
  }

  /** Jump to a stage (debug). Applies every earlier step's side effects without the cinematics. */
  async debugGoto(stage) {
    const idx = STAGES.indexOf(stage);
    if (idx < 0) { console.warn('[puzzles] unknown stage', stage); return; }
    const g = this.game, w = g.world, H = w.handles || {}, f = this.flags;
    this._started = true;
    if (idx >= 1 && !f.blackout) { f.note1 = true; this._doBlackout({ quiet: true }); }
    if (idx >= 2 && !f.flashlight) this._takeItem('flashlight', { quiet: true });
    if (idx >= 3) {
      if (!f.breaker) {
        f.breaker = true; f.summoned = true; f.summonDone = true;
        try { await H['powerBox.lever']?.setOn?.(true); } catch (e) { console.warn(e); }
        if (!w.power) w.setPower(true);
      } else f.summonDone = true;
      this._advance();
    }
    if (idx >= 4) {
      f.boxNote = true;
      if (!f.boxOpen) {
        f.boxOpen = true;
        CLUES.forEach((k, i) => { this.found[k] = this.code[i]; });
        g.ui?.setClues?.({ ...this.found });
        try { await H['lockedBox.lock']?.open?.(); await H['lockedBox.lid']?.open?.(); } catch (e) { console.warn(e); }
      }
      if (!f.key) this._takeItem('key', { quiet: true });
    }
    if (idx >= 5) { await this._unlockDoor(); this._win(); }
    this._advance();
    this._setObjective(this._objectiveText(), true);
  }

  // =================================================================== helpers

  _makeCode() {
    let q = null;
    try { q = new URLSearchParams(location.search).get('code'); } catch (e) { /* no location */ }
    if (this.game.debug && q && /^[1-9]{4}$/.test(q)) return q;
    let s = '';
    for (let i = 0; i < 4; i++) s += String(1 + Math.floor(Math.random() * 9));
    return s;
  }

  _digits() { return { duck: this.code[0], horse: this.code[1], clock: this.code[2], tv: this.code[3] }; }

  _cycle(id, lines) {
    const n = this._seen['cycle.' + id] || 0;
    this._seen['cycle.' + id] = n + 1;
    return lines[n % lines.length];
  }

  _find(names) {
    for (const n of names) {
      const o = this.game.scene.getObjectByName(n);
      if (o) return o;
    }
    return null;
  }

  _isDescendant(obj, ancestor) {
    for (let n = obj; n; n = n.parent) if (n === ancestor) return true;
    return false;
  }

  /** Invisible (material.visible=false) but ray-testable box, for things that have no usable scene object. */
  _proxy(name, size, pos) {
    const m = new THREE.Mesh(
      new THREE.BoxGeometry(size[0], size[1], size[2]),
      new THREE.MeshBasicMaterial({ visible: false, side: THREE.DoubleSide }),
    );
    m.name = 'interact_' + name;
    m.position.set(pos[0], pos[1], pos[2]);
    m.castShadow = false; m.receiveShadow = false;
    m.userData.interactProxy = true;
    this.game.scene.add(m);
    m.updateMatrixWorld(true);
    this._proxies.push(m);
    return m;
  }

  _objPos(obj) {
    const v = new THREE.Vector3();
    if (obj?.getWorldPosition) obj.getWorldPosition(v);
    return v;
  }

  _hpos(h) {
    const v = new THREE.Vector3();
    if (!h) return v;
    if (h.worldPosition) {
      try { const r = h.worldPosition(v); if (r && r.isVector3) return r === v ? v : v.copy(r); } catch (e) { /* fall through */ }
    }
    if (h.object?.getWorldPosition) h.object.getWorldPosition(v);
    else if (h.getWorldPosition) h.getWorldPosition(v);
    return v;
  }

  _panelPos() {
    const H = this.game.world.handles || {};
    const h = H['powerBox.lever'] || H['powerBox.door'];
    const v = h ? this._hpos(h) : null;
    if (v && v.lengthSq() > 1e-6) return v;
    const p = L.PROPS.powerBox.pos;
    return new THREE.Vector3(p[0], p[1], p[2] + 0.1);
  }

  _looksAt(target, minDot, maxDist, needLos) {
    if (!target) return false;
    const cam = this.game.camera;
    cam.getWorldPosition(this._camPos);
    cam.getWorldDirection(this._camDir);
    const to = this._tmp.subVectors(target, this._camPos);
    const d = to.length();
    if (d > maxDist || d < 1e-3) return false;
    if (this._camDir.dot(to) / d < minDot) return false;
    if (needLos && this.game.world.lineBlocked?.(this._camPos, target)) return false;
    return true;
  }

  _noise(position, loudness, source) {
    if (!position) return;
    this.game.events.emit('noise', { position: position.clone(), loudness, source });
  }

  _sfx(name, position, volume) {
    try {
      const o = {};
      if (position) o.position = position.clone();
      if (volume !== undefined) o.volume = volume;
      return this.game.audio?.play?.(name, o);
    } catch (e) { console.warn('[puzzles] sfx', name, e); return null; }
  }

  _say(text, seconds, opts) {
    if (!text) return;
    try { this.game.ui?.subtitle?.(fr(text), seconds ?? Math.max(2.5, text.length * 0.06), opts); } catch (e) { console.warn(e); }
  }

  _script(fn) {
    const p = Promise.resolve().then(fn);
    p.catch((e) => console.error('[puzzles] script', e));
    return p;
  }

  /** Promise resolved after `seconds` of game time (advances only while playing). */
  _wait(seconds) {
    return new Promise((resolve) => { this._waits.push({ t: seconds, resolve }); });
  }

  _tickWaits(dt) {
    const w = this._waits;
    for (let i = w.length - 1; i >= 0; i--) {
      const it = w[i];
      it.t -= dt;
      if (it.t <= 0) { w[i] = w[w.length - 1]; w.pop(); it.resolve(); }
    }
  }

  _tween(duration, fn) {
    return new Promise((resolve) => {
      try { fn(0); } catch (e) { console.warn(e); }
      this._tweens.push({ t: 0, dur: Math.max(1e-3, duration), fn, resolve });
    });
  }

  _tickTweens(dt) {
    const tw = this._tweens;
    for (let i = tw.length - 1; i >= 0; i--) {
      const it = tw[i];
      it.t += dt;
      const k = Math.min(1, it.t / it.dur);
      try { it.fn(k); } catch (e) { console.warn(e); }
      if (k >= 1) { tw[i] = tw[tw.length - 1]; tw.pop(); it.resolve(); }
    }
  }

  /** Lift + tilt a small object so its underside faces the camera, hold, put it back exactly. */
  async _tiltReveal(obj, onRevealed) {
    if (!obj || obj.userData._tilting) { onRevealed?.(); return; }
    obj.userData._tilting = true;
    const p0 = obj.position.clone(), q0 = obj.quaternion.clone();
    const wp = obj.getWorldPosition(new THREE.Vector3());
    const d = this.game.camera.getWorldPosition(new THREE.Vector3()).sub(wp).setY(0);
    if (d.lengthSq() < 1e-6) d.set(0, 0, 1);
    d.normalize();
    const parentQ = new THREE.Quaternion();
    if (obj.parent) obj.parent.getWorldQuaternion(parentQ);
    const inv = parentQ.clone().invert();
    const axis = new THREE.Vector3(-d.z, 0, d.x).applyQuaternion(inv).normalize(); // rotates -Y toward the camera
    const ps = obj.parent ? obj.parent.getWorldScale(new THREE.Vector3()).x || 1 : 1;
    const lift = new THREE.Vector3(0, 0.12 / ps, 0).applyQuaternion(inv);
    const qr = new THREE.Quaternion();
    const gen = this._gen;
    const pose = (e) => {
      qr.setFromAxisAngle(axis, 1.15 * e);
      obj.quaternion.copy(qr).multiply(q0);
      obj.position.copy(p0).addScaledVector(lift, e);
    };
    try {
      await this._tween(0.4, (k) => pose(ease(k)));
      if (gen !== this._gen) return;
      onRevealed?.();
      await this._wait(1.6);
      if (gen !== this._gen) return;
      await this._tween(0.4, (k) => pose(1 - ease(k)));
    } finally {
      obj.position.copy(p0); obj.quaternion.copy(q0);
      obj.userData._tilting = false;
    }
  }
}
