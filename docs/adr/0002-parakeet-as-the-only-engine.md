---
status: accepted
---

# Parakeet as the only transcription engine

Sottovoce uses one engine, Parakeet through FluidAudio, as Takku does: local, 25 European languages, already proven, and less prone than Whisper to inventing text over music and silence, which matters for films. It prefers **Parakeet Ultra** (Takku's default, the most accurate) and accepts **Parakeet v3** (what Ultra was trained from) when that is the only one already on the Mac, so two Macs may subtitle with different models; with neither present it downloads Ultra. Parakeet takes no language, so the language cannot be forced.

Parakeet's timings come per sub-word token, joined into words with their own start and end time (quantised to 80 ms). The spike in issue 02 (2026-11-24) confirmed it against Apple's SpeechTranscriber: equal timing in Italian, better in English, 4–5× faster, much better Italian punctuation. ADR 0008, which briefly added Apple as a second engine, was rejected on that evidence.

## Considered Options

- **Apple SpeechTranscriber**: see ADR 0008.
- **Whisper (WhisperKit)**: slower, and hallucinates over music and silence.
