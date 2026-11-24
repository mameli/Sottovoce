---
status: proposed
---

# Two Engines: Parakeet and Apple SpeechTranscriber

Sottovoce offers two Engines. **Parakeet** through FluidAudio, as in Takku: local, 25 European languages, detects the language by itself (so it cannot be forced), and less prone than Whisper to inventing text over music and silence. It prefers Parakeet Ultra and accepts v3 when that is the only one already on the Mac, so two Macs may subtitle with different models; with neither present it downloads Ultra. **Apple SpeechTranscriber**, on macOS 26 and later only: two to three times faster, per-run timings precise to the sample, models managed by macOS, but about 10 languages and the language must be given up front, which is why `--language` exists for this Engine only.

The default is whichever wins the spike in issue 02 on word-timing accuracy, which the Short Style depends on; status stays `proposed` until then.

## Considered Options

- **Whisper (WhisperKit)**: slower, and hallucinates over music and silence; rejected.
- **Parakeet only**: simpler, but gives up Apple's speed and timing precision on macOS 26.
