"""Generates placeholder sound effects and a music loop into assets/audio/.

Swap these for real audio later; the file names are what the game loads.
Run: python3 tool/make_placeholder_sounds.py
"""
import math
import random
import struct
import wave

RATE = 22050
random.seed(7)


def write(name, samples):
    with wave.open(f"assets/audio/{name}", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))


def env(i, n, attack=0.005, release=1.0):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1 - i / n) ** release


def tone(freq_start, freq_end, dur, vol=0.6, noise=0.0, release=2.0, wave_fn=math.sin):
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        f = freq_start + (freq_end - freq_start) * i / n
        phase += 2 * math.pi * f / RATE
        s = wave_fn(phase) * (1 - noise) + (random.uniform(-1, 1) * noise)
        out.append(s * vol * env(i, n, release=release))
    return out


def square(p):
    return 1.0 if math.sin(p) >= 0 else -1.0


write("hit_light.wav", tone(420, 160, 0.09, vol=0.5, noise=0.55, release=3))
write("hit_heavy.wav", tone(220, 50, 0.22, vol=0.8, noise=0.45, release=2))
write("ko.wav", [a + b for a, b in zip(
    tone(900, 120, 0.7, vol=0.45, noise=0.3, release=1.5),
    tone(120, 40, 0.7, vol=0.5, release=1.2))])
write("jump.wav", tone(300, 620, 0.12, vol=0.3, release=1.5, wave_fn=square))
write("dodge.wav", tone(1200, 500, 0.14, vol=0.25, noise=0.8, release=1))
write("ui_click.wav", tone(880, 880, 0.05, vol=0.3, release=3, wave_fn=square))

# 8-second loop: bass + arpeggio in A minor at 120 bpm.
beat = 0.5
notes = [220.0, 261.63, 329.63, 392.0]
bass = [110.0, 87.31, 98.0, 82.41]
music = [0.0] * int(RATE * 8)
for bar in range(4):
    for step in range(8):
        start = int(RATE * (bar * 2 + step * beat / 2))
        f = notes[(step + bar) % 4] * (2 if step % 4 == 3 else 1)
        for i, s in enumerate(tone(f, f, beat / 2, vol=0.12, release=2, wave_fn=square)):
            if start + i < len(music):
                music[start + i] += s
    start = int(RATE * bar * 2)
    for i, s in enumerate(tone(bass[bar], bass[bar], 2.0, vol=0.22, release=0.6)):
        music[start + i] += s
write("music_flat_arena.wav", music)
print("done")
