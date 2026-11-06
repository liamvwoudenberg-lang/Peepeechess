import {
  UNIT_DESIGNS,
  type Army,
  type CaptureProfile,
  type Weapon,
} from "./battleProfiles";
import type { PieceSymbol } from "./types";

type Tone = {
  frequency: number;
  end?: number;
  seconds: number;
  delay?: number;
  gain: number;
  wave?: OscillatorType;
  noise?: boolean;
  filter?: number;
  pan?: number;
};
export const WEAPON_TONES: Record<
  Weapon,
  { base: number; ring: number; noise: number; wave: OscillatorType }
> = {
  sword_shield: { base: 245, ring: 1570, noise: 1900, wave: "triangle" },
  lance: { base: 118, ring: 820, noise: 850, wave: "triangle" },
  warhammer: { base: 70, ring: 390, noise: 650, wave: "sine" },
  sun_staff: { base: 523, ring: 1047, noise: 4500, wave: "sine" },
  sunblade: { base: 330, ring: 1318, noise: 2600, wave: "triangle" },
  greatsword: { base: 150, ring: 790, noise: 1450, wave: "triangle" },
  twin_daggers: { base: 510, ring: 2360, noise: 4800, wave: "triangle" },
  wind_bow: { base: 425, ring: 1870, noise: 5300, wave: "sine" },
  longbow: { base: 235, ring: 1250, noise: 3600, wave: "sine" },
  moon_staff: { base: 660, ring: 1760, noise: 4200, wave: "sine" },
  moonblades: { base: 440, ring: 2093, noise: 3800, wave: "triangle" },
  leafblade: { base: 380, ring: 1710, noise: 3400, wave: "triangle" },
  rust_axe: { base: 137, ring: 630, noise: 1000, wave: "sawtooth" },
  bone_spear: { base: 109, ring: 910, noise: 1700, wave: "triangle" },
  ossuary_maul: { base: 55, ring: 280, noise: 580, wave: "sine" },
  grave_staff: { base: 174, ring: 415, noise: 2800, wave: "sine" },
  soul_scythe: { base: 196, ring: 740, noise: 2300, wave: "sawtooth" },
  executioner: { base: 82, ring: 490, noise: 1100, wave: "triangle" },
};
// Synthesized foley stays local and small; every weapon uses a distinct recipe.
export class BattleAudio {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private enabled = true;
  private active = new Set<AudioScheduledSourceNode>();
  private noise: AudioBuffer | null = null;
  private lastStep = 0;
  setEnabled(enabled: boolean) {
    this.enabled = enabled;
    if (this.master && this.ctx)
      this.master.gain.setTargetAtTime(
        enabled ? 0.48 : 0,
        this.ctx.currentTime,
        0.02,
      );
    if (!enabled)
      for (const voice of this.active) {
        try {
          voice.stop();
        } catch {}
      }
  }
  unlock() {
    if (!this.enabled || typeof window === "undefined") return;
    try {
      const Audio = window.AudioContext || (window as any).webkitAudioContext;
      if (!Audio) return;
      if (!this.ctx) {
        this.ctx = new Audio();
        this.master = this.ctx.createGain();
        this.master.gain.value = 0.48;
        const compressor = this.ctx.createDynamicsCompressor();
        compressor.threshold.value = -18;
        compressor.ratio.value = 5;
        this.master.connect(compressor);
        compressor.connect(this.ctx.destination);
      }
      if (this.ctx.state === "suspended")
        void this.ctx.resume().catch(() => {});
    } catch {}
  }
  private tone(t: Tone) {
    if (!this.enabled) return;
    this.unlock();
    const ctx = this.ctx;
    if (
      !ctx ||
      !this.master ||
      ctx.state !== "running" ||
      this.active.size >= 20
    )
      return;
    const start = ctx.currentTime + (t.delay || 0),
      gain = ctx.createGain(),
      pan =
        typeof ctx.createStereoPanner === "function"
          ? ctx.createStereoPanner()
          : ctx.createGain();
    if ("pan" in pan)
      pan.pan.value = Math.max(-0.75, Math.min(0.75, t.pan || 0));
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(
      Math.max(0.0002, t.gain),
      start + 0.008,
    );
    gain.gain.exponentialRampToValueAtTime(0.0001, start + t.seconds);
    gain.connect(pan);
    pan.connect(this.master);
    let source: AudioScheduledSourceNode;
    if (t.noise) {
      if (!this.noise) {
        this.noise = ctx.createBuffer(
          1,
          Math.floor(ctx.sampleRate * 0.5),
          ctx.sampleRate,
        );
        const buffer = this.noise.getChannelData(0);
        let seed = 12345;
        for (let i = 0; i < buffer.length; i++) {
          seed = (seed * 1664525 + 1013904223) >>> 0;
          buffer[i] = (seed / 4294967296) * 2 - 1;
        }
      }
      const noise = ctx.createBufferSource(),
        filter = ctx.createBiquadFilter();
      noise.buffer = this.noise;
      noise.loop = true;
      filter.type = "bandpass";
      filter.frequency.value = t.filter || t.frequency;
      filter.Q.value = 0.7;
      noise.connect(filter);
      filter.connect(gain);
      source = noise;
      source.onended = () => {
        filter.disconnect();
      };
    } else {
      const osc = ctx.createOscillator();
      osc.type = t.wave || "sine";
      osc.frequency.setValueAtTime(t.frequency, start);
      osc.frequency.exponentialRampToValueAtTime(
        Math.max(25, t.end || t.frequency * 0.65),
        start + t.seconds,
      );
      osc.connect(gain);
      source = osc;
    }
    this.active.add(source);
    const cleanup = source.onended;
    source.onended = (e) => {
      if (typeof cleanup === "function") cleanup.call(source, e);
      this.active.delete(source);
      source.disconnect();
      gain.disconnect();
      pan.disconnect();
    };
    source.start(start);
    source.stop(start + t.seconds + 0.015);
  }
  step(army: Army, type: PieceSymbol, pan = 0) {
    if (typeof performance === "undefined") return;
    const now = performance.now();
    if (now - this.lastStep < 95) return;
    this.lastStep = now;
    const gait = UNIT_DESIGNS[army][type].gait;
    if (gait === "float") {
      this.tone({
        frequency: army === "skeletons" ? 360 : 1200,
        end: 500,
        seconds: 0.12,
        gain: 0.011,
        wave: "sine",
        pan,
      });
      return;
    }
    const horse = type === "n";
    this.tone({
      frequency: horse
        ? 86
        : army === "elves"
          ? 170
          : army === "skeletons"
            ? 390
            : 110,
      end: 45,
      seconds: horse ? 0.07 : 0.055,
      gain: horse ? 0.07 : 0.035,
      wave: "triangle",
      pan,
    });
    if (horse)
      this.tone({
        frequency: 112,
        end: 55,
        seconds: 0.055,
        delay: 0.065,
        gain: 0.05,
        wave: "triangle",
        pan,
      });
    this.tone({
      frequency: army === "skeletons" ? 1900 : army === "elves" ? 4200 : 1100,
      noise: true,
      seconds: 0.045,
      gain: army === "elves" ? 0.015 : 0.026,
      pan,
    });
  }
  windup(profile: CaptureProfile, pan = 0) {
    const r = WEAPON_TONES[profile.weapon];
    this.tone({
      frequency: r.noise * 0.8,
      filter: r.noise * 0.8,
      noise: true,
      seconds: 0.17,
      gain: 0.035,
      pan,
    });
    if (
      profile.vfx === "sun" ||
      profile.vfx === "moon" ||
      profile.vfx === "soul"
    )
      this.tone({
        frequency: r.base * 0.6,
        end: r.base,
        seconds: 0.25,
        gain: 0.035,
        wave: "sine",
        pan,
      });
  }
  impact(profile: CaptureProfile, pan = 0, secondary = false) {
    const r = WEAPON_TONES[profile.weapon],
      magic = ["sun", "moon", "soul"].includes(profile.vfx),
      amount = secondary ? 0.55 : 1;
    this.tone({
      frequency: r.base,
      end: r.base * (magic ? 0.88 : 0.4),
      seconds: magic ? 0.34 : 0.14,
      gain: 0.09 * amount,
      wave: r.wave,
      pan,
    });
    this.tone({
      frequency: r.ring,
      end: r.ring * 0.8,
      seconds: 0.18 + profile.armor * 0.12,
      gain: 0.045 * amount,
      wave: "sine",
      delay: 0.01,
      pan,
    });
    this.tone({
      frequency: r.noise,
      noise: true,
      seconds: 0.08 + profile.armor * 0.045,
      gain: 0.05 * amount,
      pan,
    });
    if (profile.weapon === "twin_daggers" || profile.weapon === "moonblades")
      this.tone({
        frequency: r.ring * 1.25,
        end: r.ring,
        delay: 0.07,
        seconds: 0.1,
        gain: 0.026,
        pan,
      });
    if (profile.weapon === "longbow" || profile.weapon === "wind_bow")
      this.tone({
        frequency: 320,
        end: 100,
        delay: 0.045,
        seconds: 0.085,
        gain: 0.045,
        wave: "sine",
        pan,
      });
    if (magic)
      for (let i = 1; i < 4; i++)
        this.tone({
          frequency:
            r.base *
            (profile.attackerArmy === "skeletons"
              ? [1, 1.19, 1.41, 2][i]
              : [1, 1.25, 1.5, 2][i]),
          end: r.base * 0.9,
          delay: i * 0.04,
          seconds: 0.27,
          gain: 0.022,
          pan,
        });
  }
  defeat(profile: CaptureProfile, pan = 0) {
    if (profile.defenderArmy === "skeletons") {
      for (let i = 0; i < 5; i++)
        this.tone({
          frequency: 530 + i * 170,
          end: 170 + i * 40,
          seconds: 0.045 + i * 0.008,
          delay: i * 0.038,
          gain: 0.038 - i * 0.004,
          wave: "triangle",
          pan,
        });
      this.tone({
        frequency: 2400,
        noise: true,
        seconds: 0.23,
        gain: 0.025,
        pan,
      });
    } else if (profile.defenderArmy === "elves") {
      for (let i = 0; i < 3; i++)
        this.tone({
          frequency: 1760 / (1 + i * 0.27),
          end: 880,
          seconds: 0.24,
          delay: i * 0.06,
          gain: 0.018,
          pan,
        });
    } else {
      this.tone({
        frequency: 89,
        end: 35,
        seconds: 0.19,
        gain: 0.055,
        wave: "sine",
        pan,
      });
      this.tone({
        frequency: 2300,
        noise: true,
        seconds: 0.14,
        delay: 0.06,
        gain: 0.025,
        pan,
      });
    }
    if (profile.defender === "k")
      this.tone({
        frequency: 320,
        end: 150,
        seconds: 0.32,
        delay: 0.1,
        gain: 0.035,
        wave: "triangle",
        pan,
      });
  }
  promote(army: Army, pan = 0) {
    const notes =
      army === "skeletons"
        ? [220, 261.6, 311.1, 440]
        : army === "elves"
          ? [523, 783.99, 1046, 1568]
          : [392, 493.88, 587.33, 783.99];
    notes.forEach((frequency, i) =>
      this.tone({
        frequency,
        seconds: 0.26,
        delay: i * 0.055,
        gain: 0.022,
        pan,
      }),
    );
  }
}
export const battleAudio = new BattleAudio();
