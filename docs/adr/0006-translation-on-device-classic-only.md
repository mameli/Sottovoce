# Translation on the Mac with Apple's Translation framework, Classic only

A Translation is written from the Classic Cues of the Transcript with Apple's on-device Translation framework, keeping ADR 0001. The framework translates without a window only on macOS 26 (`TranslationSession(installedSource:target:)`), and a process without a window cannot download languages, so the CLI fails with instructions when a language is missing and the GUI offers the download. Translation is refused for the Short Style: one or three translated words per Cue break the word order of the target language.

## Considered Options

- **A local LLM**: more languages and control, but a large extra model and slower; kept as the alternative if Apple's quality falls short.
