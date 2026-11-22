"""Bake short mono foley and the red ship's motor from deterministic synthesis."""

from pathlib import Path
from wave import open as open_wave

import numpy as np


RATE = 24_000
OUTPUT = Path(__file__).resolve().parents[1] / "coop" / "sounds"
RNG = np.random.default_rng(91268)


def seconds(duration):
    return np.arange(round(duration * RATE)) / RATE


def attack(t, duration):
    return np.sin(0.5 * np.pi * np.clip(t / duration, 0, 1)) ** 2


def strike(t, at, onset, decay):
    age = np.maximum(t - at, 0)
    return attack(age, onset) * np.exp(-age / decay)


def noise(t, low, high):
    frequencies = np.fft.rfftfreq(t.size, 1 / RATE)
    spectrum = np.fft.rfft(RNG.normal(size=t.size))
    band = (frequencies / (frequencies + low)) ** 2 / (1 + (frequencies / high) ** 4)
    samples = np.fft.irfft(spectrum * band, n=t.size)
    return samples / samples.std()


def tone(t, hz):
    return np.sin(2 * np.pi * hz * t)


def debris(t, count, start, end, high):
    sound = np.zeros_like(t)
    for _ in range(count):
        at = RNG.uniform(start, end)
        age = np.maximum(t - at, 0)
        frequency = RNG.uniform(high * 0.23, high)
        sound += RNG.uniform(0.05, 0.18) * tone(age, frequency) * strike(t, at, 0.001, RNG.uniform(0.0025, 0.012))
    return sound


def wooden_step():
    t = seconds(0.30)
    heel = strike(t, 0.018, 0.012, 0.047)
    toe = strike(t, RNG.uniform(0.092, 0.120), 0.019, 0.039)
    RNG.bit_generator.advance(1)  # Historical unused weight draw in the wooden take.
    board = np.zeros_like(t)
    for frequency, weight_at_frequency in [(122, 0.50), (207, 0.23), (343, 0.13), (628, 0.06)]:
        board += weight_at_frequency * tone(t, frequency * RNG.uniform(0.93, 1.07))
    tap = noise(t, 620, 3200) * (0.30 * heel + 0.10 * toe)
    return t, tap + board * (heel + 0.37 * toe)


def water(duration, size, underwater=False):
    t = seconds(duration)
    wash = strike(t, 0.016, 0.018 + 0.024 * size, 0.052 + 0.078 * size)
    droplets = strike(t, 0.060, 0.031, 0.105 + 0.057 * size)
    high = 800 if underwater else 2800 + 600 * size
    sound = 0.57 * noise(t, 110, high * 0.40) * wash
    sound += 0.21 * noise(t, 330, high) * droplets
    for _ in range(18):
        at = RNG.uniform(0.025, min(duration * 0.75, 0.26 + size * 0.13))
        age = np.maximum(t - at, 0)
        hz = RNG.uniform(165, 525) if underwater else RNG.uniform(340, 1450)
        bubble = np.sin(2 * np.pi * (hz * age + hz * 6 * age * age))
        sound += RNG.uniform(0.03, 0.10) * bubble * strike(t, at, 0.003, RNG.uniform(0.009, 0.027))
    return t, sound


def stone_contact(surface):
    t = seconds(0.29)
    earth = surface == "earth"
    wood = surface == "wood"
    knock = strike(t, 0.010, 0.0025, 0.022 if earth else 0.035)
    body = 118 if earth else (226 if wood else 535)
    sound = 0.43 * noise(t, 255, 1900 if earth else 4600) * knock
    sound += (tone(t, body) * 0.38 + tone(t, body * 1.68) * 0.11) * knock
    sound += 0.19 * noise(t, 440, 2800) * strike(t, 0.067, 0.004, 0.029)
    sound += debris(t, 9, 0.046, 0.15, 1250 if earth else 2400)
    return t, sound


def throw():
    t = seconds(0.20)
    pull = noise(t, 240, 1400) * strike(t, 0.007, 0.022, 0.041)
    release = noise(t, 600, 3800) * strike(t, 0.044, 0.011, 0.026)
    return t, pull * 0.43 + release * 0.32


def gunshot(rifle):
    t = seconds(0.44 if rifle else 0.27)
    crack = noise(t, 760, 5850) * strike(t, 0.001, .002, .022 if rifle else .014)
    thump = tone(t, 77 if rifle else 132) * strike(t, .002, .004, .056 if rifle else .025)
    tail = noise(t, 210, 1900) * strike(t, .022, .013, .098 if rifle else .056)
    return t, 0.64 * crack + (0.63 if rifle else 0.36) * thump + 0.26 * tail


def motor(phase):
    return sum(weight * tone(phase, harmonic) for harmonic, weight in [(1, 0.67), (2, 0.25), (3, 0.13), (5, 0.07)])


def engine_idle():
    # Frequencies complete integral cycles and the spectral noise is circular.
    t = seconds(2.0)
    drift = 0.022 * tone(t, 1.5) + 0.014 * tone(t, 2.5)
    pulse = 0.88 + 0.066 * tone(t, 11) + 0.034 * tone(t, 3.5)
    sound = 0.55 * motor(62 * t + drift) + 0.17 * tone(t, 93) + 0.07 * tone(t, 223.5)
    sound += 0.16 * noise(t, 80, 640) + 0.038 * noise(t, 320, 1750)
    return t, sound * pulse


def engine_switch(starting):
    t = seconds(1.12 if starting else 0.91)
    time = t / t[-1]
    rpm = 29 + 38 * attack(time, 0.68) if starting else 18 + 43 * (1 - time) ** 1.5
    phase = np.cumsum(rpm) / RATE
    motor_level = attack(t, 0.56) if starting else np.exp(-t / 0.25)
    air = 0.22 * noise(t, 70, 710) + 0.075 * noise(t, 390, 1800)
    motor_sound = (0.57 * motor(phase) + 0.06 * tone(phase, 7.5) + air) * motor_level
    relay = noise(t, 280, 2200) * strike(t, 0.028 if starting else 0.41, 0.003, 0.025)
    return t, motor_sound + 0.44 * relay


def atlas_zoom(closer):
    t = seconds(0.095)
    low, high = (510, 760) if closer else (670, 405)
    frequency = low + (high - low) * (1.0 - np.exp(-t / .024))
    phase = 2 * np.pi * np.cumsum(frequency) / RATE
    tick = (np.sin(phase) + .24 * np.sin(phase * 2.09) + .07 * np.sin(phase * 3.61)) * np.exp(-t / .029)
    return t, tick + .21 * noise(t, 1320, 2870) * np.exp(-t / .011)


def write(name, signal, peak, looping=False):
    t, sound = signal
    if not looping:
        sound *= attack(t, 0.007) * attack(t[-1] - t, min(0.080, t[-1] * 0.28))
    limited = np.tanh(sound)
    samples = np.round(limited * peak * 32767 / np.max(np.abs(limited))).astype("<i2")
    with open_wave(str(OUTPUT / (name + ".wav")), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(samples.tobytes())


def main():
    OUTPUT.mkdir(exist_ok=True)
    # Skip the retired trail/leaf takes in the seeded sequence so rebuilding
    # reproduces the original wooden boards, water and subsequent effects.
    for number, retired_draws in enumerate((14871, 14862), start=1):
        RNG.bit_generator.advance(retired_draws)
        write(f"step-wood-{number}", wooden_step(), 0.62)
        write(f"step-wade-{number}", water(0.33, 0.2), 0.59)
        write(f"swim-stroke-{number}", water(0.41, 0.39), 0.59)
    write("swim-deep", water(0.40, 0.44, underwater=True), 0.54)
    write("swim-entry", water(0.68, 1.0), 0.73)
    write("stone-throw", throw(), 0.55)
    for surface in ("earth", "wood", "rock"):
        write("stone-" + surface, stone_contact(surface), 0.66)
    write("stone-water", water(0.48, 0.62), 0.66)
    write("engine-start", engine_switch(True), 0.70)
    write("engine-loop", engine_idle(), 0.72, looping=True)
    write("engine-stop", engine_switch(False), 0.66)
    write("rifle-shot", gunshot(True), 0.74)
    write("pistol-shot", gunshot(False), 0.68)
    write("atlas-zoom-in", atlas_zoom(True), 0.51)
    write("atlas-zoom-out", atlas_zoom(False), 0.47)


if __name__ == "__main__":
    main()
