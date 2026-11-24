# Changelog

## 0.1.0 (2026-11-24)

First release of Sottovoce:

- Local on-device transcription on Apple Silicon with Parakeet (FluidAudio), automatic language detection, and Silero VAD speech-only filtering.
- Model borrowing from Sister Apps (Takku and Dimmela) with automatic first-use download into `~/Library/Application Support/Sottovoce/Models`.
- Classic (1–2 lines, punctuation/pause-aware) and Short (1–3 words, frame-snapped) Styles, SRT and VTT Formats, UTF-8 without BOM.
- Agent-friendly CLI (`sottovoce <files> [--style] [--words] [--format] [--speakers] [--translate] [--force] [--json]`), Watched Folder (`sottovoce watch <folder>`), and local stdio MCP server (`sottovoce mcp`) with agent skill plugin.
- Native macOS SwiftUI app with drag-and-drop Queue, overwrite confirmation, and Settings (Models, Vocabulary, Translation).
- Opt-in Speaker diarization (Nemotron 3), Vocabulary (`~/.sottovoce/vocabulary.md`), Homebrew `ffmpeg` fallback for MKV/WebM, and Classic on-device Translation (macOS 26+).
