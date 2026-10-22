"""
Procedural Audio & Sound Effects Generator for Amiga Game Engine
================================================================

Synthesizes high-quality, authentic retro Amiga sound effects using physical modeling,
FM, subtractive, and wavetable synthesis techniques without external sample dependencies.

Amiga Audio Hardware & Driver Specifications:
---------------------------------------------
1. Paula Custom Chip (MOS Technology 8364):
   - 4 independent DMA audio channels (2 Left, 2 Right).
   - Linear 8-bit signed PCM format (-128 to +127).
   - Standard replay sample rate: 11,025 Hz (Paula period 322 for PAL machines:
     Period = 3,546,895 Hz / 11,025 Hz = 322).
2. PTPlayer Driver Compatibility (Frank Wille):
   - Every raw sample file must begin with a 2-byte zero word (dc.w 0) as an idle loop
     sentinel when played via _mt_playfx / _mt_loopfx.
   - Total file length must be an even number of bytes for 68000 word alignment.
3. Dual-Format Pipeline:
   - Exports raw 8-bit PCM to `assets/fx/<name>.raw` for direct inclusion into Chip RAM.
   - Exports standard 16-bit 11,025 Hz mono WAV to `scratch/sfx_preview/<name>.wav`
     for verification on host development systems.
"""

import math
import struct
import os
import wave

SAMPLE_RATE = 11025
AMIGA_PAL_CLOCK = 3546895
PAULA_PERIOD = round(AMIGA_PAL_CLOCK / SAMPLE_RATE) # 3546895 / 11025 = 322

os.makedirs("assets/fx", exist_ok=True)
os.makedirs("scratch/sfx_preview", exist_ok=True)

def export_sfx(name, samples):
    # Ensure length is even (Amiga word alignment)
    if len(samples) % 2 != 0:
        samples.append(0)
        
    # Amiga raw format for PTPlayer:
    # First 2 bytes (one word) MUST be 0 (idle loop word)
    raw_bytes = bytearray([0, 0])
    for s in samples:
        # clamp to signed 8-bit -128..127
        val = int(round(s))
        val = max(-128, min(127, val))
        raw_bytes.append(val & 0xFF)
        
    raw_path = os.path.join("assets/fx", f"{name}.raw")
    with open(raw_path, "wb") as f:
        f.write(raw_bytes)
        
    # Also write a standard 16-bit mono WAV for easy listening/verification on PC
    wav_path = os.path.join("scratch/sfx_preview", f"{name}.wav")
    with wave.open(wav_path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wav_data = bytearray()
        for s in samples:
            val = int(round(s * 256.0))
            val = max(-32768, min(32767, val))
            wav_data.extend(struct.pack("<h", val))
        wf.writeframes(wav_data)
        
    num_words = len(raw_bytes) // 2
    print(f"Exported {name:18s}: {len(raw_bytes):5d} bytes ({num_words:4d} words) | Period: {PAULA_PERIOD} | Dur: {len(samples)/SAMPLE_RATE:.2f}s")
    return raw_path, num_words

# 1. Cane Whoosh / Swish (Air displacement + whip arc)
def gen_cane_whoosh():
    dur = 0.14 # 140ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    # Bandpass swept noise + low whistle
    # Frequency sweeps down from 1600 Hz to 250 Hz
    phase = 0.0
    import random
    random.seed(42)
    # Simple lowpass state
    lp = 0.0
    for i in range(n):
        t = i / n
        env = math.sin(t * math.pi) ** 1.5 # smooth bell envelope
        # Filtered swoosh noise
        cutoff = 1800.0 * (1.0 - t * 0.75) # sweep down
        alpha = min(1.0, 2.0 * math.pi * cutoff / SAMPLE_RATE)
        noise = (random.random() * 2.0 - 1.0) * 110.0
        lp += alpha * (noise - lp)
        
        # Sub-bass whoosh body (sine pitch-drop 220Hz down to 80Hz)
        freq = 240.0 * (1.0 - t * 0.7)
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        tone = math.sin(phase) * 60.0
        
        s = (lp * 0.6 + tone * 0.5) * env
        samples.append(s)
    return samples

# 2. Crate Impact / Heavy Drop (Deep pitch-dropped thump + crunch transient)
def gen_crate_impact():
    dur = 0.18 # 180ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    import random
    random.seed(101)
    phase = 0.0
    for i in range(n):
        t = i / n
        # Fast attack, exponential decay
        env = math.exp(-t * 14.0)
        
        # Initial wooden click/crack transient in first 15ms
        transient = 0.0
        if t < 0.08:
            trans_env = math.exp(-t * 45.0)
            transient = (random.random() * 2.0 - 1.0) * 115.0 * trans_env
            # Add wood body resonance around 320 Hz
            transient += math.sin(2.0 * math.pi * 320.0 * (i / SAMPLE_RATE)) * 80.0 * trans_env
            
        # Heavy sub-bass thud: drops quickly from 140 Hz down to 45 Hz
        freq = 45.0 + 95.0 * math.exp(-t * 22.0)
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        body = (math.sin(phase) + 0.3 * math.sin(phase * 2.0)) * 105.0 * env
        
        s = transient * 0.6 + body * 0.8
        samples.append(s)
    return samples

# 3. Enemy Stun / Dizzy Stars (Cartoon boing / star chime ping)
def gen_enemy_stun():
    dur = 0.24 # 240ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    # Upward pitch sweep (boing) with vibrato ring (sparkle)
    phase1 = 0.0
    phase2 = 0.0
    for i in range(n):
        t = i / n
        env = math.exp(-t * 7.5) * (1.0 - math.exp(-t * 60.0)) # sharp attack, ring decay
        
        # Boing sweep: 250 Hz rising to 650 Hz with pitch bend
        freq1 = 250.0 + 400.0 * (1.0 - math.exp(-t * 18.0))
        # Add dizzy wobble vibrato (16 Hz)
        wobble = 25.0 * math.sin(2.0 * math.pi * 16.0 * t)
        phase1 += 2.0 * math.pi * (freq1 + wobble) / SAMPLE_RATE
        
        # High harmonic chime (stars sparkle, 1320 Hz)
        freq2 = 1320.0 + 30.0 * math.sin(2.0 * math.pi * 20.0 * t)
        phase2 += 2.0 * math.pi * freq2 / SAMPLE_RATE
        chime_env = math.exp(-t * 12.0)
        
        # Mix boing body + sparkling chime
        s = (math.sin(phase1) * 85.0 + math.sin(phase2) * 45.0 * chime_env) * env
        samples.append(s)
    return samples

# 4. Duckling Rescue (Cute duckling chirp / cheerful high chime)
def gen_duck_rescue():
    dur = 0.26 # 260ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    # Part 1: Cute duckling "peep/quack" (0..120ms): 1400 Hz sweep down to 900 Hz with formant
    # Part 2: Joyful sparkle chime (80..260ms): two ascending bell notes (1760 Hz -> 2637 Hz, A6 to E7)
    phase_peep = 0.0
    phase_chime1 = 0.0
    phase_chime2 = 0.0
    for i in range(n):
        t = i / n
        s = 0.0
        
        # Duckling peep (first half)
        if t < 0.5:
            t_p = t / 0.5
            p_env = math.sin(t_p * math.pi) ** 1.2
            # Peep freq drops from 1500 to 950 Hz
            f_p = 950.0 + 550.0 * (1.0 - t_p)
            phase_peep += 2.0 * math.pi * f_p / SAMPLE_RATE
            # Add nasal formant overtone
            peep = (math.sin(phase_peep) + 0.4 * math.sin(phase_peep * 2.0)) * 90.0 * p_env
            s += peep
            
        # Chime 1 (starting at t=0.15)
        if t >= 0.15:
            t_c1 = (t - 0.15) / 0.85
            c1_env = math.exp(-t_c1 * 12.0)
            f_c1 = 1760.0 # A6
            phase_chime1 += 2.0 * math.pi * f_c1 / SAMPLE_RATE
            s += math.sin(phase_chime1) * 55.0 * c1_env
            
        # Chime 2 (higher sparkle at t=0.35)
        if t >= 0.35:
            t_c2 = (t - 0.35) / 0.65
            c2_env = math.exp(-t_c2 * 10.0)
            f_c2 = 2637.0 # E7
            phase_chime2 += 2.0 * math.pi * f_c2 / SAMPLE_RATE
            s += math.sin(phase_chime2) * 60.0 * c2_env
            
        samples.append(s)
    return samples

# 5. Oxygen Refill / Bubble (Aquatic bubble pop + restorative rising chime)
def gen_oxygen_refill():
    dur = 0.22 # 220ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    phase1 = 0.0
    phase2 = 0.0
    for i in range(n):
        t = i / n
        # Bubble 1 (0..90ms): pitch rising 400 Hz -> 850 Hz
        b1 = 0.0
        if t < 0.45:
            t_b = t / 0.45
            b_env = math.sin(t_b * math.pi)
            f_b = 400.0 + 450.0 * (t_b ** 2.0)
            phase1 += 2.0 * math.pi * f_b / SAMPLE_RATE
            b1 = math.sin(phase1) * 85.0 * b_env
            
        # Bubble 2 / chime (70ms..220ms): pitch rising 700 Hz -> 1400 Hz
        b2 = 0.0
        if t >= 0.3:
            t_b2 = (t - 0.3) / 0.7
            b2_env = math.exp(-t_b2 * 9.0)
            f_b2 = 700.0 + 700.0 * math.sqrt(t_b2)
            phase2 += 2.0 * math.pi * f_b2 / SAMPLE_RATE
            b2 = math.sin(phase2) * 75.0 * b2_env
            
        samples.append(b1 + b2)
    return samples

# 6. Crate Push / Scrape (Wood & floor friction scratch)
def gen_crate_push():
    dur = 0.15 # 150ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    import random
    random.seed(77)
    lp = 0.0
    phase = 0.0
    for i in range(n):
        t = i / n
        env = math.sin(t * math.pi) ** 1.3
        # Textured friction noise (bandpassed ~450 Hz)
        noise = (random.random() * 2.0 - 1.0) * 100.0
        cutoff = 480.0 + 120.0 * math.sin(2.0 * math.pi * 30.0 * t) # jittery friction
        alpha = min(1.0, 2.0 * math.pi * cutoff / SAMPLE_RATE)
        lp += alpha * (noise - lp)
        
        # Heavy low resonance (110 Hz rumble)
        phase += 2.0 * math.pi * 110.0 / SAMPLE_RATE
        rumble = math.sin(phase) * 50.0
        
        s = (lp * 0.7 + rumble * 0.4) * env
        samples.append(s)
    return samples

# 7. Player Death - Option 1 (Default): Fatal Hit Impact, 6-Note Minor Stumble & Floor Flop
# Timed to match Mia's 48-frame (0.96s) 4-cel death collapse animation:
#   Cel 0 (staggered): crack, cane clatter snap, body thud, startled vocal chirp/gasp
#   Cel 1 (knees buckle): cascading staccato descending run (B5 -> A5 -> G#5)
#   Cel 2 (pitching forward): descending run (F#5 -> E5 -> D5/C5) with detuned Paula chorus
#   Cel 3 (flat on floor): ground thud impact, comedic sad slide & wobble, soft dust puff
def gen_player_die():
    dur = 0.88 # 880ms (44 PAL frames)
    n = int(dur * SAMPLE_RATE)
    samples = []
    import random
    random.seed(42)

    # Descending 6-note stumble progression (Minor / Dorian tumble):
    # B5 (987Hz) -> A5 (880Hz) -> G#5 (830Hz) -> F#5 (740Hz) -> E5 (659Hz) -> D5->C5 (587->523Hz)
    notes = [
        (0.12, 0.21, 987.77, 0.06), # B5
        (0.21, 0.30, 880.00, 0.06), # A5
        (0.30, 0.39, 830.61, 0.07), # G#5
        (0.39, 0.49, 739.99, 0.08), # F#5
        (0.49, 0.59, 659.25, 0.09), # E5
        (0.59, 0.70, 587.33, 0.12), # D5 sliding towards C5
    ]

    phase_hit = 0.0
    phase_melody1 = 0.0
    phase_melody2 = 0.0
    phase_sub = 0.0
    phase_flop = 0.0
    noise_lp = 0.0
    noise_hp = 0.0

    for i in range(n):
        t = i / SAMPLE_RATE

        # -------------------------------------------------------------
        # 1. Fatal Hit Impact & Shock (0.00 - 0.13s)
        # -------------------------------------------------------------
        hit_sig = 0.0
        if t < 0.13:
            # Crack / slap transient (first 30ms)
            env_crack = math.exp(-t * 85.0)
            raw_noise = (random.random() * 2.0 - 1.0) * 115.0
            noise_lp += 0.32 * (raw_noise - noise_lp)
            crack = (noise_lp * 0.7 + raw_noise * 0.3) * env_crack

            # Cane clatter snap (high transient click at t=0.010s)
            cane_snap = 0.0
            if 0.010 <= t < 0.050:
                t_cs = t - 0.010
                cane_snap = math.sin(2.0 * math.pi * 1450.0 * t_cs) * math.exp(-t_cs * 160.0) * 80.0

            # Visceral body thud (pitch drops 260 Hz -> 55 Hz)
            f_thump = 55.0 + 205.0 * math.exp(-t * 32.0)
            phase_hit += 2.0 * math.pi * f_thump / SAMPLE_RATE
            thump = math.sin(phase_hit) * 115.0 * math.exp(-t * 26.0)

            # Startled vocal chirp / gasp (t = 0.02..0.12s)
            chirp = 0.0
            if 0.02 <= t < 0.12:
                tc = t - 0.02
                env_chirp = max(0.0, math.sin((tc / 0.10) * math.pi)) ** 1.3
                f_chirp = 620.0 + 380.0 * math.sin((tc / 0.10) * math.pi * 0.85)
                phase_sub += 2.0 * math.pi * f_chirp / SAMPLE_RATE
                chirp = (math.sin(phase_sub) + 0.35 * math.sin(phase_sub * 2.0)) * 75.0 * env_chirp

            hit_sig = crack * 0.55 + cane_snap * 0.45 + thump * 0.70 + chirp * 0.45

        # -------------------------------------------------------------
        # 2. Descending Melodic Run (0.12 - 0.70s)
        # -------------------------------------------------------------
        melody_sig = 0.0
        for st, en, freq, sag in notes:
            if st <= t < en:
                nt = (t - st) / (en - st)
                # Sharp punchy attack (7ms), decaying sustain
                if nt < 0.09:
                    env_m = nt / 0.09
                else:
                    env_m = math.exp(-(nt - 0.09) * 3.8)
                if nt > 0.85:
                    env_m *= (1.0 - (nt - 0.85) / 0.15)

                # Pitch sag within each note (dramatic weight/stumble)
                f_cur = freq * (1.0 - nt * sag)

                # Detuned Paula synth dual-voice (warm chorus sheen)
                phase_melody1 += 2.0 * math.pi * f_cur / SAMPLE_RATE
                phase_melody2 += 2.0 * math.pi * (f_cur * 1.006) / SAMPLE_RATE

                # Rich retro pulse/saw harmonic structure
                p1 = (phase_melody1 % (2.0 * math.pi)) / (2.0 * math.pi)
                pulse1 = 0.95 if p1 < 0.38 else -0.95
                sine1 = math.sin(phase_melody1)
                harm1 = math.sin(phase_melody1 * 2.0)
                sine2 = math.sin(phase_melody2)

                voice = (sine1 * 0.45 + pulse1 * 0.28 + harm1 * 0.18 + sine2 * 0.22)
                melody_sig = voice * env_m * 88.0
                break

        # -------------------------------------------------------------
        # 3. Floor Flop & Comedic Sad Slide Settle (0.68 - 0.88s)
        # -------------------------------------------------------------
        flop_sig = 0.0
        if t >= 0.68:
            tf = t - 0.68
            env_f = math.exp(-tf * 13.0)

            # Ground impact thud (pitch drops 110 Hz -> 45 Hz)
            f_flop = 45.0 + 65.0 * math.exp(-tf * 22.0)
            phase_flop += 2.0 * math.pi * f_flop / SAMPLE_RATE
            thud = math.sin(phase_flop) * 100.0 * env_f

            # Comedic sad slide down: 175 Hz -> 58 Hz with 13 Hz wobble
            f_slide = 58.0 + 117.0 * math.exp(-tf * 9.0)
            wobble = 14.0 * math.sin(2.0 * math.pi * 13.0 * tf) * math.exp(-tf * 5.5)
            phase_sub += 2.0 * math.pi * (f_slide + wobble) / SAMPLE_RATE
            slide_tone = (math.sin(phase_sub) + 0.45 * math.sin(phase_sub * 2.0) + 0.2 * math.sin(phase_sub * 3.0)) * 80.0 * math.exp(-tf * 7.5)

            # Soft dust puff noise (highpassed rustle)
            dust_raw = (random.random() * 2.0 - 1.0) * 35.0
            noise_hp = dust_raw - 0.85 * noise_hp
            dust_puff = noise_hp * math.exp(-tf * 22.0)

            flop_sig = thud * 0.70 + slide_tone * 0.65 + dust_puff * 0.30

        # Master mix with soft analog saturation
        total = hit_sig + melody_sig + flop_sig
        total = math.tanh(total / 92.0) * 115.0

        # Master tail fadeout at very end
        if t > 0.82:
            fade = (0.88 - t) / 0.06
            total *= max(0.0, fade)

        samples.append(total)

    return samples

# Player Death - Option 2: Classic Arcade Melodic Jingle (Mario / Giana Sisters style)
def gen_player_die_arcade_jingle():
    dur = 0.90
    n = int(dur * SAMPLE_RATE)
    samples = []
    import random
    random.seed(123)

    jingle_notes = [
        (0.10, 0.20, 493.88, 0.0), # B4
        (0.20, 0.34, 698.46, 0.0), # F5
        (0.39, 0.48, 698.46, 0.0), # F5
        (0.48, 0.57, 698.46, 0.0), # F5
        (0.57, 0.66, 659.25, 0.0), # E5
        (0.66, 0.75, 587.33, 0.0), # D5
        (0.75, 0.90, 523.25, 1.0), # C5 finale with slide & sad vibrato
    ]

    phase_hit = 0.0
    phase_melody = 0.0
    phase_sub = 0.0
    noise_lp = 0.0

    for i in range(n):
        t = i / SAMPLE_RATE

        hit_sig = 0.0
        if t < 0.10:
            env_crack = math.exp(-t * 95.0)
            noise = (random.random() * 2.0 - 1.0) * 115.0
            noise_lp += 0.28 * (noise - noise_lp)
            crack = (noise_lp * 0.75 + noise * 0.25) * env_crack
            f_thump = 55.0 + 200.0 * math.exp(-t * 38.0)
            phase_hit += 2.0 * math.pi * f_thump / SAMPLE_RATE
            thump = math.sin(phase_hit) * 115.0 * math.exp(-t * 30.0)
            hit_sig = crack * 0.65 + thump * 0.75

        melody_sig = 0.0
        for st, en, freq, is_tail in jingle_notes:
            if st <= t < en:
                nt = (t - st) / (en - st)
                if nt < 0.08:
                    env_m = nt / 0.08
                else:
                    if is_tail > 0.5:
                        env_m = math.exp(-(nt - 0.08) * 2.2)
                    else:
                        env_m = math.exp(-(nt - 0.08) * 4.8)
                if nt > 0.88 and is_tail < 0.5:
                    env_m *= (1.0 - (nt - 0.88) / 0.12)

                vib = 0.0
                f_cur = freq
                if is_tail > 0.5:
                    f_cur = freq * (1.0 - nt * 0.35)
                    if nt > 0.2:
                        vib = 12.0 * math.sin(2.0 * math.pi * 6.5 * (t - st))
                else:
                    f_cur = freq * (1.0 - nt * 0.05)

                phase_melody += 2.0 * math.pi * (f_cur + vib) / SAMPLE_RATE

                p = (phase_melody % (2.0 * math.pi)) / (2.0 * math.pi)
                pulse = 0.9 if p < 0.35 else -0.9
                sine = math.sin(phase_melody)
                harm2 = math.sin(phase_melody * 2.0)
                harm3 = math.sin(phase_melody * 3.0)
                tone = sine * 0.50 + pulse * 0.30 + harm2 * 0.22 + harm3 * 0.10
                melody_sig = tone * env_m * 85.0
                break

        flop_sig = 0.0
        if t >= 0.74:
            tf = t - 0.74
            env_f = math.exp(-tf * 15.0)
            f_flop = 75.0 * math.exp(-tf * 16.0)
            phase_sub += 2.0 * math.pi * f_flop / SAMPLE_RATE
            flop_sig = math.sin(phase_sub) * 70.0 * env_f

        total = hit_sig + melody_sig + flop_sig
        total = math.tanh(total / 95.0) * 115.0
        if t > 0.85:
            fade = (0.90 - t) / 0.05
            total *= max(0.0, fade)
        samples.append(total)

    return samples

# 8. Underwater Air Bubble (Crisp resonant water bubble "bloop")
def gen_air_bubble():
    dur = 0.09 # 90ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    phase = 0.0
    for i in range(n):
        t = i / n
        # Smooth attack, exponential decay
        env = math.sin(t * math.pi) * math.exp(-t * 3.5)
        
        # Upward frequency sweep (420 Hz -> 980 Hz)
        freq = 420.0 + 560.0 * (t ** 1.4)
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        
        # Resonant sine bubble + slight high click on detachment
        tone = math.sin(phase) * 95.0
        if t < 0.08:
            tone += math.sin(phase * 3.0) * 30.0 * (1.0 - t / 0.08)
            
        s = tone * env
        samples.append(s)
    return samples

# 9. Triumphant Level Complete Fanfare (Heroic ascending brass/chime fanfare + finale vibrato)
def gen_level_complete():
    notes = [
        (0.00, 0.12, 261.63), # C4
        (0.12, 0.24, 329.63), # E4
        (0.24, 0.36, 392.00), # G4
        (0.36, 0.52, 523.25), # C5
        (0.52, 0.64, 587.33), # D5
        (0.64, 0.80, 659.25), # E5
        (0.80, 1.25, 783.99), # G5 finale
    ]
    dur = 1.25 # 1.25s
    n = int(dur * SAMPLE_RATE)
    samples = []
    
    phase_main = 0.0
    phase_harm = 0.0
    phase_sub = 0.0
    phase_shimmer = 0.0
    
    for i in range(n):
        t = i / SAMPLE_RATE
        note_freq = 783.99
        note_start = 0.80
        note_end = 1.25
        is_finale = False
        
        for st, en, freq in notes:
            if st <= t < en:
                note_freq = freq
                note_start = st
                note_end = en
                is_finale = (st >= 0.80)
                break
                
        note_t = (t - note_start) / (note_end - note_start)
        
        if not is_finale:
            if note_t < 0.15:
                env = note_t / 0.15
            else:
                env = math.exp(-(note_t - 0.15) * 3.5)
            if note_t > 0.90:
                env *= (1.0 - (note_t - 0.90) / 0.10)
        else:
            if note_t < 0.08:
                env = note_t / 0.08
            else:
                env = math.exp(-(note_t - 0.08) * 1.8)
                
        vib = 0.0
        if is_finale and note_t > 0.2:
            vib = 4.5 * math.sin(2.0 * math.pi * 5.5 * (t - 0.8))
            
        cur_freq = note_freq + vib
        phase_main += 2.0 * math.pi * cur_freq / SAMPLE_RATE
        phase_harm += 2.0 * math.pi * (cur_freq * 2.0) / SAMPLE_RATE
        phase_sub  += 2.0 * math.pi * (cur_freq * 0.5) / SAMPLE_RATE
        
        tone = math.sin(phase_main) * 75.0 + math.sin(phase_harm) * 35.0 + math.sin(phase_sub) * 20.0
        
        shimmer = 0.0
        if is_finale:
            phase_shimmer += 2.0 * math.pi * 1568.0 / SAMPLE_RATE # G6 high sparkle
            shimmer = math.sin(phase_shimmer) * 25.0 * env
            
        s = (tone * env + shimmer) * 0.85
        samples.append(s)
    return samples

# 10. Amiga Game Engine Intro Splash Trumpet Fanfare
def gen_intro_fanfare():
    # 'Ta-ta-ta, Taa-ta-TAAAH!'
    # Regal Royal Amiga Engine Fanfare (two brass voices: lead trumpet + harmony horn)
    notes_lead = [
        (0.00, 0.10, 392.00), # G4
        (0.10, 0.20, 392.00), # G4
        (0.20, 0.30, 392.00), # G4
        (0.30, 0.58, 523.25), # C5
        (0.58, 0.72, 659.25), # E5
        (0.72, 1.50, 783.99), # G5 Finale
    ]
    notes_harm = [
        (0.00, 0.10, 196.00), # G3
        (0.10, 0.20, 196.00), # G3
        (0.20, 0.30, 196.00), # G3
        (0.30, 0.58, 329.63), # E4
        (0.58, 0.72, 392.00), # G4
        (0.72, 1.50, 523.25), # C5
    ]
    dur = 1.50
    n = int(dur * SAMPLE_RATE)
    samples = []
    
    phase1_f = 0.0
    phase1_2 = 0.0
    phase1_3 = 0.0
    phase1_4 = 0.0
    
    phase2_f = 0.0
    phase2_2 = 0.0
    phase2_3 = 0.0
    
    for i in range(n):
        t = i / SAMPLE_RATE
        lead_nt = notes_lead[-1]
        for nt in notes_lead:
            if nt[0] <= t < nt[1]:
                lead_nt = nt
                break
        harm_nt = notes_harm[-1]
        for nt in notes_harm:
            if nt[0] <= t < nt[1]:
                harm_nt = nt
                break
                
        st, en, f1 = lead_nt
        _,  _,  f2 = harm_nt
        is_finale = (st >= 0.72)
        note_t = (t - st) / (en - st)
        
        # Envelope: punchy brass attack (12ms), sustain, release
        if note_t < 0.12:
            env = note_t / 0.12
        else:
            if is_finale:
                env = math.exp(-(note_t - 0.12) * 1.6)
            else:
                env = math.exp(-(note_t - 0.12) * 2.8)
        if note_t > 0.90:
            env *= (1.0 - (note_t - 0.90) / 0.10)
            
        # Vibrato on sustained finale
        vib = 0.0
        if is_finale and note_t > 0.15:
            vib = 4.2 * math.sin(2.0 * math.pi * 5.4 * (t - 0.72))
            
        cur_f1 = f1 + vib
        cur_f2 = f2 + vib * 0.7
        
        # Advance phases
        phase1_f += 2.0 * math.pi * cur_f1 / SAMPLE_RATE
        phase1_2 += 2.0 * math.pi * (cur_f1 * 2.0) / SAMPLE_RATE
        phase1_3 += 2.0 * math.pi * (cur_f1 * 3.0) / SAMPLE_RATE
        phase1_4 += 2.0 * math.pi * (cur_f1 * 4.0) / SAMPLE_RATE
        
        phase2_f += 2.0 * math.pi * cur_f2 / SAMPLE_RATE
        phase2_2 += 2.0 * math.pi * (cur_f2 * 2.0) / SAMPLE_RATE
        phase2_3 += 2.0 * math.pi * (cur_f2 * 3.0) / SAMPLE_RATE
        
        # Harmonic spectrum shaping for brass trumpet
        t1 = (math.sin(phase1_f) * 0.44 + 
              math.sin(phase1_2) * 0.28 + 
              math.sin(phase1_3) * 0.18 + 
              math.sin(phase1_4) * 0.10)
        t2 = (math.sin(phase2_f) * 0.42 + 
              math.sin(phase2_2) * 0.26 + 
              math.sin(phase2_3) * 0.14)
              
        mix = (t1 * 0.62 + t2 * 0.45) * env * 115.0
        samples.append(mix)
        
    return samples

export_sfx("sfx_cane", gen_cane_whoosh())
export_sfx("sfx_crate_impact", gen_crate_impact())
export_sfx("sfx_enemy_stun", gen_enemy_stun())
export_sfx("sfx_duck_rescue", gen_duck_rescue())
export_sfx("sfx_oxygen", gen_oxygen_refill())
export_sfx("sfx_crate_push", gen_crate_push())
export_sfx("sfx_player_die", gen_player_die())
export_sfx("sfx_player_die_arcade", gen_player_die_arcade_jingle())
export_sfx("sfx_air_bubble", gen_air_bubble())
export_sfx("sfx_level_complete", gen_level_complete())
export_sfx("sfx_intro_fanfare", gen_intro_fanfare())

# ==============================================================================
# 11. Blade Runner Game Over - Option 1: Vangelis CS-80 Melancholic Brass Swell
# ==============================================================================
def gen_vangelis_cs80():
    dur = 2.80
    n = int(dur * SAMPLE_RATE)
    voices = [
        (73.42,  0.45, 0.0),   # Sub D2
        (146.83, 0.70, 0.6),   # Root D3 + detune
        (146.83, 0.70, -0.6),  # Root D3 - detune
        (174.61, 0.55, 0.5),   # Minor 3rd F3
        (220.00, 0.40, -0.4),  # 5th A3
    ]
    phases = [0.0] * len(voices)
    delay_len = int(SAMPLE_RATE * 0.16)
    delay_buf = [0.0] * delay_len
    delay_idx = 0
    samples = []
    
    for i in range(n):
        t = i / SAMPLE_RATE
        if t < 0.22:
            env = (t / 0.22) ** 1.6
        elif t < 1.10:
            env = 1.0 - (t - 0.22) * 0.15
        else:
            env = 0.87 * math.exp(-(t - 1.10) * 1.85)
            
        pitch_mod = 0.0
        if t > 0.45:
            vib_amp = min(1.0, (t - 0.45) / 0.6) * 1.8
            pitch_mod += math.sin(2.0 * math.pi * 5.2 * (t - 0.45)) * vib_amp
        if t > 1.20:
            drop_factor = min(1.0, (t - 1.20) / 1.5)
            pitch_mod -= drop_factor * 8.5
            
        filter_harmonics = 3 + int(5 * env)
        sig = 0.0
        for v_idx, (base_f, vol, detune) in enumerate(voices):
            f = base_f + detune + pitch_mod * (base_f / 146.83)
            phases[v_idx] += 2.0 * math.pi * f / SAMPLE_RATE
            ph = phases[v_idx]
            v_sig = 0.0
            for h in range(1, filter_harmonics + 1):
                amp = (1.0 / h) * (1.0 - (h / (filter_harmonics + 1)) * 0.3)
                v_sig += math.sin(ph * h) * amp
            sig += v_sig * vol
            
        sig = math.tanh(sig * 0.75) * env * 105.0
        delayed = delay_buf[delay_idx]
        delay_buf[delay_idx] = sig + delayed * 0.45
        delay_idx = (delay_idx + 1) % delay_len
        out_sample = sig * 0.75 + delayed * 0.35
        samples.append(out_sample)
    return samples

# ==============================================================================
# 12. Blade Runner Game Over: Spinner "ENVIRON CTR" Terminal Klaxon (3-Note Cadence)
# ==============================================================================
# Expands the original 2-note alert into a complete 3-note descending sequence
# spaced at exact 24-frame (480ms at 50Hz PAL) intervals:
#   Pulse 1 (t=0.00s, frame 0):  High Alert Ping   D5 (587.33Hz) + F#5 (739.99Hz) + 120Hz ring
#   Pulse 2 (t=0.48s, frame 24): Mid Warning Chime  A4 (440.00Hz) + C#5 (554.37Hz) + 95Hz ring
#   Pulse 3 (t=0.96s, frame 48): Low Shutdown Tone  D4 (293.66Hz) + F#4 (369.99Hz) + 72Hz ring
# Followed by sustained CRT power drain and low ambient hum (55Hz -> 28Hz) until t=2.50s.
def gen_spinner_klaxon(mode="major"):
    dur = 2.50
    n = int(dur * SAMPLE_RATE)
    samples = []
    phase_p1_a = 0.0
    phase_p1_b = 0.0
    phase_p2_a = 0.0
    phase_p2_b = 0.0
    phase_p3_a = 0.0
    phase_p3_b = 0.0
    phase_hum = 0.0
    import random
    random.seed(82)
    noise_lp = 0.0
    
    # In major mode, Pulse 3 is F#4 (369.99Hz - complete D major triad cadence)
    # In minor mode, Pulse 3 is F4  (349.23Hz - Picardy third in reverse, tragic minor)
    p3_f_b = 369.99 if mode == "major" else 349.23
    
    for i in range(n):
        t = i / SAMPLE_RATE
        out = 0.0
        
        # Pulse 1: Alert Ping D5 587Hz + F#5 740Hz + 120Hz ring (Frame 0..24, 0.00..0.48s)
        if 0.0 <= t < 0.48:
            pt = t
            p_env = math.exp(-pt * 9.5)
            phase_p1_a += 2.0 * math.pi * 587.33 / SAMPLE_RATE
            phase_p1_b += 2.0 * math.pi * 739.99 / SAMPLE_RATE
            ring = math.sin(2.0 * math.pi * 120.0 * pt)
            tone_a = math.sin(phase_p1_a) + 0.35 * math.sin(phase_p1_a * 3.0)
            tone_b = math.sin(phase_p1_b) + 0.30 * math.sin(phase_p1_b * 3.0)
            out += (tone_a * 0.50 + tone_b * 0.40 + ring * 0.15) * p_env * 110.0
            
        # Pulse 2: Mid warning chime A4 440Hz + C#5 554Hz + 95Hz ring (Frame 24..48, 0.48..0.96s)
        if 0.48 <= t < 0.96:
            pt = t - 0.48
            p_env = math.exp(-pt * 8.5)
            phase_p2_a += 2.0 * math.pi * 440.00 / SAMPLE_RATE
            phase_p2_b += 2.0 * math.pi * 554.37 / SAMPLE_RATE
            ring = math.sin(2.0 * math.pi * 95.0 * pt)
            tone_a = math.sin(phase_p2_a) + 0.35 * math.sin(phase_p2_a * 3.0)
            tone_b = math.sin(phase_p2_b) + 0.30 * math.sin(phase_p2_b * 3.0)
            out += (tone_a * 0.55 + tone_b * 0.45 + ring * 0.15) * p_env * 115.0

        # Pulse 3: Low terminal power-down chime D4 293.66Hz + F#4 369.99Hz + 72Hz ring (Frame 48+, 0.96..1.70s)
        if 0.96 <= t < 1.70:
            pt = t - 0.96
            p_env = math.exp(-pt * 6.5)
            phase_p3_a += 2.0 * math.pi * 293.66 / SAMPLE_RATE
            phase_p3_b += 2.0 * math.pi * p3_f_b / SAMPLE_RATE
            ring = math.sin(2.0 * math.pi * 72.0 * pt)
            tone_a = math.sin(phase_p3_a) + 0.38 * math.sin(phase_p3_a * 3.0)
            tone_b = math.sin(phase_p3_b) + 0.32 * math.sin(phase_p3_b * 3.0)
            out += (tone_a * 0.55 + tone_b * 0.45 + ring * 0.15) * p_env * 115.0
            
        # Analog CRT power drain & low ambient hum (55Hz -> 28Hz)
        if t >= 0.10:
            hum_t = t - 0.10
            hum_f = 55.0 - 27.0 * (min(1.0, hum_t / 2.0) ** 1.8)
            phase_hum += 2.0 * math.pi * hum_f / SAMPLE_RATE
            hum_env = math.exp(-hum_t * 1.4)
            hum = (math.sin(phase_hum) * 0.7 + math.sin(phase_hum * 2.0) * 0.3) * hum_env * 65.0
            noise = (random.random() * 2.0 - 1.0) * 15.0 * hum_env
            noise_lp += 0.08 * (noise - noise_lp)
            out += hum + noise_lp
            
        out = math.tanh(out / 100.0) * 115.0
        if t > 2.40:
            out *= (2.50 - t) / 0.10
        samples.append(out)
    return samples

export_sfx("sfx_game_over", gen_spinner_klaxon(mode="major"))
export_sfx("sfx_game_over_minor", gen_spinner_klaxon(mode="minor"))

# ==============================================================================
# 13. VHS Tape Rewind / Move Unwind (Deck engage, high-speed motor whirl, tape chatter, brake snap)
# ==============================================================================
def gen_vhs_rewind():
    # Exactly 0.60s (30 frames at 50Hz PAL) to match VHS_EFFECT_DURATION
    dur = 0.60
    n = int(dur * SAMPLE_RATE)
    samples = []
    import random
    random.seed(999)
    
    # Pre-generate noise for tape friction
    noise_buf = [(random.random() * 2.0 - 1.0) for _ in range(n)]
    
    # 2-pole bandpass filter state for tape hiss around 2.4 kHz
    fc = 2400.0 / SAMPLE_RATE
    r = 0.82
    b1 = -2.0 * r * math.cos(2.0 * math.pi * fc)
    b2 = r * r
    y1 = 0.0
    y2 = 0.0
    
    phase_m = 0.0
    phase_c1 = 0.0
    phase_c2 = 0.0
    
    for i in range(n):
        t = i / SAMPLE_RATE
        
        # 1. Start Mechanical Solenoid Click (t = 0.005..0.040s)
        mech_start = 0.0
        if 0.005 <= t < 0.040:
            dt1 = t - 0.005
            env1 = math.exp(-dt1 * 220.0)
            click1 = (math.sin(2.0 * math.pi * 320.0 * dt1) * 0.6 + math.sin(2.0 * math.pi * 2600.0 * dt1) * 0.4) * env1
            dt2 = t - 0.020
            click2 = 0.0
            if dt2 >= 0:
                env2 = math.exp(-dt2 * 160.0)
                click2 = (math.sin(2.0 * math.pi * 180.0 * dt2) * 0.7 + math.sin(2.0 * math.pi * 1700.0 * dt2) * 0.3) * env2
            mech_start = click1 * 0.7 + click2 * 0.9
            
        # 2. Motor Whine Frequency & Amplitude Envelope
        # Acceleration 0.03..0.16s, Sustain 0.16..0.48s, Deceleration 0.48..0.54s
        if t < 0.03:
            mfreq = 0.0
            m_env = 0.0
        elif t < 0.16:
            p = (t - 0.03) / 0.13
            mfreq = 320.0 + 1160.0 * (p ** 1.3)
            m_env = p
        elif t < 0.48:
            flutter = 45.0 * math.sin(2.0 * math.pi * 14.0 * t)
            mfreq = 1480.0 + flutter
            m_env = 1.0 + 0.18 * math.sin(2.0 * math.pi * 14.0 * t + 0.5)
        elif t < 0.54:
            p = (t - 0.48) / 0.06
            mfreq = 1480.0 * (1.0 - p ** 0.7) + 240.0 * p
            m_env = (1.0 - p)
        else:
            mfreq = 0.0
            m_env = 0.0
            
        # Motor harmonics
        phase_m += 2.0 * math.pi * mfreq / SAMPLE_RATE
        motor_tone = (
            math.sin(phase_m) * 0.50 +
            math.sin(phase_m * 2.0) * 0.28 +
            math.sin(phase_m * 3.0) * 0.14 +
            math.sin(phase_m * 4.0) * 0.08
        ) * m_env
        
        # 3. High-Speed Reverse Tape Chatter (warbling scrub audio)
        f_c1 = 1200.0 + 700.0 * math.sin(2.0 * math.pi * 26.0 * t) + 400.0 * math.cos(2.0 * math.pi * 11.0 * t)
        f_c2 = 2100.0 + 600.0 * math.sin(2.0 * math.pi * 37.0 * t + 1.2)
        phase_c1 += 2.0 * math.pi * f_c1 / SAMPLE_RATE
        phase_c2 += 2.0 * math.pi * f_c2 / SAMPLE_RATE
        tape_chatter = (math.sin(phase_c1) * 0.6 + math.sin(phase_c2) * 0.4) * m_env
        
        # 4. Filtered Tape Hiss / Air Whoosh
        x0 = noise_buf[i]
        x2 = noise_buf[i - 2] if i >= 2 else 0.0
        y0 = 0.25 * (x0 - x2) - b1 * y1 - b2 * y2
        y2 = y1
        y1 = y0
        tape_hiss = y0 * m_env * 0.55
        
        # 5. Stop Mechanical Brake Clunk & Solenoid Snap (t = 0.52..0.60s)
        mech_stop = 0.0
        if 0.520 <= t < 0.600:
            dt_s1 = t - 0.525
            env_s1 = math.exp(-dt_s1 * 140.0) if dt_s1 >= 0 else 0.0
            thump = (math.sin(2.0 * math.pi * 130.0 * dt_s1) * 0.8 + math.sin(2.0 * math.pi * 2400.0 * dt_s1) * 0.2) * env_s1
            
            dt_s2 = t - 0.540
            env_s2 = math.exp(-dt_s2 * 180.0) if dt_s2 >= 0 else 0.0
            snap = (math.sin(2.0 * math.pi * 280.0 * dt_s2) * 0.4 + math.sin(2.0 * math.pi * 3200.0 * dt_s2) * 0.6) * env_s2
            mech_stop = thump * 0.9 + snap * 0.7
            
        # Combine layers
        sig = (
            mech_start * 55.0 +
            motor_tone * 45.0 +
            tape_chatter * 35.0 +
            tape_hiss * 45.0 +
            mech_stop * 65.0
        )
        
        # Fade out very end cleanly
        if t > 0.58:
            sig *= (0.60 - t) / 0.02
            
        samples.append(sig)
        
    return samples

export_sfx("sfx_rewind", gen_vhs_rewind())




