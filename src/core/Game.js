import * as THREE from 'three';
import { EventBus } from './EventBus.js';
import { Settings } from './Settings.js';
import { Assets } from './Assets.js';
import { Input } from './Input.js';
import { Renderer } from '../render/Renderer.js';
import { World } from '../world/World.js';
import { Player } from '../player/Player.js';
import { Interaction } from '../game/Interaction.js';
import { Inventory } from '../game/Inventory.js';
import { Puzzles } from '../game/Puzzles.js';
import { Gardienne } from '../entity/Gardienne.js';
import { AudioEngine } from '../audio/Audio.js';
import { UI } from '../ui/UI.js';

export const NIGHTS_TOTAL = 3;

/**
 * Game orchestrator. Owns every system and the main loop.
 * States: 'loading' | 'menu' | 'playing' | 'paused' | 'caught' | 'gameover' | 'won'
 */
export class Game {
  constructor({ canvas, uiRoot, touchRoot, params = {} }) {
    this.canvas = canvas;
    this.uiRoot = uiRoot;
    this.touchRoot = touchRoot;
    this.params = params;
    this.debug = !!params.debug;

    this.events = new EventBus();
    this.settings = new Settings(this.events);
    this.state = 'loading';
    this.time = 0;            // seconds spent in 'playing'
    this.realTime = 0;        // seconds since start (all states)
    this.nightsTotal = NIGHTS_TOTAL;
    this.night = 1;           // 1-based current night
    this.fear = 0;            // 0..1 smoothed

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x000000);
    this.camera = new THREE.PerspectiveCamera(this.settings.get('fov'), 1, 0.03, 60);
    this.camera.rotation.order = 'YXZ';
    this.scene.add(this.camera); // so camera-attached objects (flashlight) render

    // Systems (construction order matters only for references; all heavy work happens in init()).
    this.renderer = new Renderer(this, canvas);
    this.assets = new Assets(this);
    this.input = new Input(this, touchRoot);
    this.audio = new AudioEngine(this);
    this.ui = new UI(this, uiRoot);
    this.world = new World(this);
    this.inventory = new Inventory(this);
    this.interaction = new Interaction(this);
    this.player = new Player(this);
    this.entity = new Gardienne(this);
    this.puzzles = new Puzzles(this);

    this._clock = new THREE.Clock();
    this._loop = this._loop.bind(this);
    this._pauseOnUnlock = true;
  }

  async init() {
    this.ui.init();
    this.ui.showLoading(0, 'Initialisation…');
    this.renderer.init();
    this.input.init();
    this.audio.init();
    this._wireEvents();

    await this.assets.preload((p) => this.ui.showLoading(p * 0.7, 'Chargement des modèles 3D…'));
    this.ui.showLoading(0.72, 'Construction du sous-sol…');
    await this.world.init();
    this.ui.showLoading(0.85, 'Réveil de la gardienne…');
    await this.entity.init();
    this.player.init();
    this.interaction.init();
    this.inventory.init();
    await this.puzzles.init();
    this.ui.showLoading(0.95, 'Compilation des shaders…');
    this.renderer.warmup?.();
    this.ui.showLoading(1, 'Prêt');

    if (this.debug || this.params.expose) window.__game = this;
    requestAnimationFrame(this._loop);

    if (this.params.autostart) this.start();
    else this.setState('menu');
  }

  _wireEvents() {
    const ev = this.events;
    ev.on('ui:start', () => this.start());
    ev.on('input:pause', () => {
      if (this.state === 'playing') this.pause();
      else if (this.state === 'paused') this.resume();
    });
    ev.on('input:pointerlock', ({ locked }) => {
      if (!locked && this.state === 'playing' && !this.input.isTouch && this._pauseOnUnlock && !this.ui.isModalOpen()) this.pause();
    });
    ev.on('entity:caught', () => this.onCaught());
    ev.on('game:win', () => this.onWin());
    ev.on('settings:changed', ({ key, value }) => {
      if (key === 'fov') { this.camera.fov = value; this.camera.updateProjectionMatrix(); }
    });
    window.addEventListener('resize', () => this.renderer.resize());
    document.addEventListener('visibilitychange', () => { if (document.hidden && this.state === 'playing') this.pause(); });
  }

  setState(s) {
    const prev = this.state;
    this.state = s;
    this.events.emit('game:state', { state: s, prev });
    if (s === 'menu') this.ui.showMenu();
  }

  /** Called from the menu "Jouer" button (a user gesture: safe to unlock audio + pointer lock). */
  start() {
    if (this.state === 'playing') return;
    this.ui.hideMenu();
    this.audio.unlock();
    this.input.lockPointer();
    this.setState('playing');
    this.puzzles.start();
  }

  pause() {
    if (this.state !== 'playing') return;
    this.setState('paused');
    this.audio.setPaused?.(true);
    this.input.unlockPointer();
    this.ui.showPause().then(() => this.resume());
  }

  resume() {
    if (this.state !== 'paused') return;
    this.ui.hidePause();
    this.audio.setPaused?.(false);
    this.input.lockPointer();
    this.setState('playing');
  }

  /** Open a modal UI (note, keypad) without triggering the pause-on-pointer-unlock behaviour. */
  async modal(promiseFactory) {
    this._pauseOnUnlock = false;
    this.input.unlockPointer();
    try { return await promiseFactory(); }
    finally {
      this.input.lockPointer();
      setTimeout(() => { this._pauseOnUnlock = true; }, 300);
    }
  }

  async onCaught() {
    if (this.state !== 'playing') return;
    this.setState('caught');
    this.player.enabled = false;
    await this.ui.fadeTo(1, 0.5);
    this.night += 1;
    if (this.night > this.nightsTotal) {
      this.setState('gameover');
      this.input.unlockPointer();
      await this.ui.showGameOver();
      window.location.reload();
      return;
    }
    this.input.unlockPointer();
    await this.ui.showCaught({ night: this.night, nightsTotal: this.nightsTotal });
    this.player.respawn();
    this.entity.reset('caught');
    this.world.reset('caught');
    this.puzzles.reset('caught');
    this.player.cameraOverride = false;
    this.player.enabled = true;
    this.input.lockPointer();
    this.setState('playing');
    await this.ui.fadeTo(0, 1.5);
  }

  async onWin() {
    if (this.state !== 'playing') return;
    this.setState('won');
    this.player.enabled = false;
    this.input.unlockPointer();
    await this.ui.fadeTo(1, 2.5);
    await this.ui.showWin({ time: this.time, nightsUsed: this.night, nightsTotal: this.nightsTotal });
    window.location.reload();
  }

  _loop() {
    requestAnimationFrame(this._loop);
    const dt = Math.min(this._clock.getDelta(), 0.05);
    this.realTime += dt;
    const s = this.state;
    const live = s === 'playing' || s === 'caught' || s === 'won';

    this.input.enabled = s === 'playing' && !this.ui.isModalOpen();
    this.input.update(dt);

    if (s === 'playing') this.time += dt;
    if (live) {
      this.player.update(dt);
      this.interaction.update(dt);
      this.puzzles.update(dt);
      this.entity.update(dt);
    } else if (s === 'menu' || s === 'loading') {
      this.player.updateIdleCamera?.(dt); // slow cinematic drift behind the menu
    }
    this.world.update(dt);

    const targetFear = live ? (this.entity.fear ?? 0) : 0;
    this.fear += (targetFear - this.fear) * Math.min(1, dt * 2.5);
    this.renderer.setFear?.(this.fear);
    this.audio.setFear?.(this.fear);
    this.audio.update(dt);

    this.renderer.render(dt);
    this.ui.update(dt);
    this.input.endFrame();
  }
}
