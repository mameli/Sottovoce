---
status: rejected
---

# Two Engines: Parakeet and Apple SpeechTranscriber

Proposed: offer Apple SpeechTranscriber (macOS 26+) next to Parakeet, with the winner of a word-timing spike as the default, and `--language` for Apple's engine, which needs the language up front.

Rejected on 2026-11-24 after the spike in issue 02 (a 12.6 min Italian vlog and a 19 min English tech video, YouTube's auto captions as a third opinion). Apple gave no timing advantage: equivalent in Italian, a steady 80–190 ms early in English. It was 4–5× slower than Parakeet (about 75× realtime against 275–365×), often left out commas and full stops in Italian, which the Classic Style splits on, and would have cost a language option, a Language menu and a macOS 26 gate. Parakeet stays the only engine (ADR 0002). Worth reopening only if a new Apple release beats those numbers.
