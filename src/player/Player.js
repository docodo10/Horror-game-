import * as THREE from 'three';
import * as L from '../config/layout.js';

// STUB — to be replaced by the player/input module (see ARCHITECTURE.md §Player).
// Public API (must be kept):
//   constructor(game); init(); update(dt); updateIdleCamera(dt)
//   .position (Vector3, feet)  .yaw  .pitch  .eyeHeight  .radius
//   .enabled (movement+look)   .cameraOverride (when true, Player does NOT write the camera transform)
//   .crouched  .sprinting  .moving  .stamina 0..1  .onStairs
//   .hidden (bool)  .hideSpot (HideSpot|null)
//   .flashlight { has, on, battery 0..100, light: THREE.SpotLight }
//   giveFlashlight()  setFlashlightOn(on)  addBattery(amount=60)
//   enterHide(spot)  exitHide()      animated (~0.6s) camera move into / out of the hide spot
//   respawn()                        back to layout.SPAWN, standing, flashlight state kept
//   teleport(x, y, z, yawRad, pitchRad)
//   getVisibility()                  0..1 how visible the player is to the entity right now
//   eyePosition(target?)             world position of the camera eye
// Emits: 'noise' {position, loudness, source}, 'player:flashlight' {has, on, battery},
//        'player:stamina' {value}, 'player:hide' {hidden, spotId}, 'player:bump' {tag}
export class Player {
  constructor(game) {
    this.game = game;
    this.position = new THREE.Vector3(L.SPAWN.x, 0, L.SPAWN.z);
    this.yaw = L.SPAWN.yaw; this.pitch = 0; this.eyeHeight = 1.62; this.radius = 0.25;
    this.enabled = true; this.cameraOverride = false; this.hidden = false; this.hideSpot = null;
    this.crouched = false; this.sprinting = false; this.moving = false; this.stamina = 1;
    this.flashlight = { has: false, on: false, battery: 100, light: new THREE.SpotLight(0xfff1dc, 0, 15, 0.45, 0.4, 2) };
  }
  init() {
    const cam = this.game.camera;
    cam.add(this.flashlight.light); cam.add(this.flashlight.light.target);
    this.flashlight.light.target.position.set(0, 0, -1);
    const c = this.game.params.cam?.split(',').map(Number);
    if (c && c.length >= 3) this.teleport(c[0], c[1], c[2], ((c[3] || 0) * Math.PI) / 180, ((c[4] || 0) * Math.PI) / 180);
  }
  update(dt) {
    const i = this.game.input;
    const sp = 1.9 * dt, s = Math.sin(this.yaw), c = Math.cos(this.yaw);
    const dx = (i.move.x * c - i.move.y * s) * sp, dz = (-i.move.x * s - i.move.y * c) * sp;
    if (this.enabled) this.game.world.moveCircle(this.position, dx, dz, this.radius, this.position.y + 0.3, this.position.y + 1.7);
    this.position.y = this.game.world.groundHeightAt(this.position.x, this.position.z, this.position.y);
    if (!this.cameraOverride) {
      this.game.camera.position.set(this.position.x, this.position.y + this.eyeHeight, this.position.z);
      this.game.camera.rotation.set(this.pitch, this.yaw, 0, 'YXZ');
    }
  }
  updateIdleCamera(dt) { this.update(0); }
  giveFlashlight() { this.flashlight.has = true; }
  setFlashlightOn(on) { this.flashlight.on = on; this.flashlight.light.intensity = on ? 30 : 0; }
  addBattery(a = 60) { this.flashlight.battery = Math.min(100, this.flashlight.battery + a); }
  enterHide(spot) { this.hidden = true; this.hideSpot = spot; this.game.events.emit('player:hide', { hidden: true, spotId: spot.id }); }
  exitHide() { this.hidden = false; this.hideSpot = null; this.game.events.emit('player:hide', { hidden: false }); }
  respawn() { this.position.set(L.SPAWN.x, 0, L.SPAWN.z); this.yaw = L.SPAWN.yaw; this.pitch = 0; this.hidden = false; }
  teleport(x, y, z, yaw = this.yaw, pitch = 0) { this.position.set(x, y, z); this.yaw = yaw; this.pitch = pitch; }
  getVisibility() { return 0.5; }
  eyePosition(t = new THREE.Vector3()) { return t.set(this.position.x, this.position.y + this.eyeHeight, this.position.z); }
}
