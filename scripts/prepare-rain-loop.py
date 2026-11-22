"""Prepare continuous stereo ambience from the original SkyCut forest recording."""
from pathlib import Path
import wave

import numpy as np


root = Path(__file__).resolve().parents[1]
source = root / "art/game_audio/SkyCut/生成/forest rain.wav"
target = root / "coop/sounds/ai/forest_rain.wav"
with wave.open(str(source), "rb") as recording:
    rate = recording.getframerate()
    assert recording.getnchannels() == 2 and recording.getsampwidth() == 2
    stereo = np.frombuffer(recording.readframes(recording.getnframes()), "<i2").reshape(-1, 2)

# Leave out the recording's onset and quiet tail. Wrap two rain textures across
# each other at equal power, then put the file boundary inside contiguous audio.
body = stereo[round(0.12 * rate):-round(0.20 * rate)]
overlap = round(0.64 * rate)
phase = np.linspace(0.0, np.pi / 2, overlap)[:, None]
blend = body[-overlap:] * np.cos(phase) + body[:overlap] * np.sin(phase)
loop = np.concatenate((body[overlap:-overlap], blend))
with wave.open(str(target), "wb") as output:
    output.setparams((2, 2, rate, 0, "NONE", "not compressed"))
    output.writeframes(np.clip(np.rint(loop), -32768, 32767).astype("<i2").tobytes())
