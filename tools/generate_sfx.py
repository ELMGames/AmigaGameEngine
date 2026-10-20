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

# 7. Player Death (Fatal hit impact + dramatic descending arpeggio collapse)
def gen_player_die():
    dur = 0.46 # 460ms
    n = int(dur * SAMPLE_RATE)
    samples = []
    import random
    random.seed(333)
    
    # 4 descending notes: C5 (523Hz), A4 (440Hz), F4 (349Hz), D4->D3 (293Hz -> 146Hz)
    notes = [
        (0.00, 0.10, 523.0),
        (0.10, 0.20, 440.0),
        (0.20, 0.30, 349.0),
        (0.30, 0.46, 293.0)
    ]
    
    phase = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        
        # Initial crunchy hit impact (first 25ms)
        hit = 0.0
        if t < 0.025:
            hit_env = math.exp(-t * 120.0)
            hit = (random.random() * 2.0 - 1.0) * 110.0 * hit_env
            
        # Determine active note
        note_freq = 220.0
        note_env = 0.0
        for start_t, end_t, freq in notes:
            if start_t <= t < end_t:
                rel_t = (t - start_t) / (end_t - start_t)
                # Note volume decay
                note_env = math.exp(-rel_t * 4.0)
                # Pitch bend down within each note slightly for dramatic weight
                if start_t >= 0.30:
                    # Final note slides down deep into the bass
                    slide = (1.0 - rel_t * 0.5)
                    note_freq = freq * slide
                else:
                    note_freq = freq * (1.0 - rel_t * 0.1)
                break
                
        # Warm retro tone: mix fundamental + soft 2nd harmonic (analog/chiptune warmth)
        phase += 2.0 * math.pi * note_freq / SAMPLE_RATE
        tone = (math.sin(phase) * 85.0 + math.sin(phase * 2.0) * 35.0) * note_env
        
        # Master fadeout
        master_env = 1.0 - (i / n) ** 1.5
        s = (hit * 0.7 + tone * 0.85) * master_env
        samples.append(s)
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
# 12. Blade Runner Game Over: Spinner "ENVIRON CTR" Terminal Klaxon
# ==============================================================================
def gen_spinner_klaxon():
    dur = 2.40
    n = int(dur * SAMPLE_RATE)
    samples = []
    phase_p1_a = 0.0
    phase_p1_b = 0.0
    phase_p2_a = 0.0
    phase_p2_b = 0.0
    phase_hum = 0.0
    import random
    random.seed(82)
    noise_lp = 0.0
    
    for i in range(n):
        t = i / SAMPLE_RATE
        out = 0.0
        # Pulse 1: Alert Ping D5 587Hz + F#5 740Hz + 120Hz ring
        if 0.0 <= t < 0.45:
            pt = t
            p_env = math.exp(-pt * 9.5)
            phase_p1_a += 2.0 * math.pi * 587.33 / SAMPLE_RATE
            phase_p1_b += 2.0 * math.pi * 739.99 / SAMPLE_RATE
            ring = math.sin(2.0 * math.pi * 120.0 * pt)
            tone_a = math.sin(phase_p1_a) + 0.35 * math.sin(phase_p1_a * 3.0)
            tone_b = math.sin(phase_p1_b) + 0.30 * math.sin(phase_p1_b * 3.0)
            out += (tone_a * 0.5 + tone_b * 0.4 + ring * 0.15) * p_env * 110.0
            
        # Pulse 2: Lower warning chime A4 440Hz + C#5 554Hz
        if 0.50 <= t < 0.98:
            pt = t - 0.50
            p_env = math.exp(-pt * 8.5)
            phase_p2_a += 2.0 * math.pi * 440.00 / SAMPLE_RATE
            phase_p2_b += 2.0 * math.pi * 554.37 / SAMPLE_RATE
            ring = math.sin(2.0 * math.pi * 95.0 * pt)
            tone_a = math.sin(phase_p2_a) + 0.35 * math.sin(phase_p2_a * 3.0)
            tone_b = math.sin(phase_p2_b) + 0.30 * math.sin(phase_p2_b * 3.0)
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
        samples.append(out)
    return samples

export_sfx("sfx_game_over", gen_spinner_klaxon())



