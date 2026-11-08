// Player settings, persisted in localStorage when available.
const KEY = 'lagardienne.settings.v1';

export const DEFAULT_SETTINGS = {
  quality: 'auto',      // 'auto' | 'low' | 'medium' | 'high' | 'ultra'
  sensitivity: 1.0,     // look sensitivity multiplier (0.3 .. 3)
  invertY: false,
  brightness: 1.0,      // 0.6 .. 1.6 (post-process exposure multiplier)
  volume: 0.85,         // master volume 0..1
  subtitles: true,
  fov: 70,
};

export class Settings {
  constructor(events) {
    this.events = events;
    this.values = { ...DEFAULT_SETTINGS };
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) Object.assign(this.values, JSON.parse(raw));
    } catch (_) { /* storage unavailable */ }
  }

  get(k) { return this.values[k]; }

  set(k, v) {
    this.values[k] = v;
    try { localStorage.setItem(KEY, JSON.stringify(this.values)); } catch (_) { /* ignore */ }
    this.events.emit('settings:changed', { key: k, value: v, settings: this.values });
  }
}
