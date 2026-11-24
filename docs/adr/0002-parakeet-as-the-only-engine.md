---
status: proposed
---

# Parakeet as the only transcription engine

Version 1 uses one engine, Parakeet through FluidAudio, as Takku does: local, 25 European languages, already proven, and less prone than Whisper to inventing text over music and silence, which matters for films. It prefers **Parakeet Ultra** (Takku's default, the most accurate) and accepts **Parakeet v3** (what Ultra was trained from) when that is the only one already on the Mac, so two Macs may subtitle with different models; with neither present it downloads Ultra. Parakeet takes no language, so the language cannot be forced.

Parakeet's timings come per sub-word token, so tokens are joined into words with their own start and end time; the Short Style depends on how accurate they are. Status stays `proposed` until a spike compares them with Apple's SpeechTranscriber (macOS 26) on a real video.

## Considered Options

- **Apple SpeechTranscriber**: two to three times faster with native word timings, but 10 languages and macOS 26 only. The first candidate for a second engine if the spike favours it, enabled only on macOS 26.
- **Whisper (WhisperKit)**: slower, and hallucinates over music and silence.
