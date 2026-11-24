---
name: sottovoce
description: Use when the user asks to generate, create, or export SRT or VTT subtitles for a local video or audio file on macOS (for DaVinci Resolve, CapCut, YouTube, or vertical short-form video). Uses Sottovoce's local MCP tools or CLI.
---

# Creating Subtitle Files with Sottovoce

Sottovoce transcribes local Media Files on this Mac (never uploading audio) and writes a Subtitle File next to each Media File with the same base name (`interview.mov` → `interview.srt`). Language is detected automatically.

## With the MCP tools (preferred)

1. Call `create_subtitles` with the absolute `path` to the Media File and optional parameters:
   - `style`: `"classic"` (default, 1–2 lines as in films/YouTube) or `"short"` (1–3 words for vertical short-form video).
   - `words`: `1`, `2`, or `3` (default `1`, used with `"short"`).
   - `format`: `"srt"` (default) or `"vtt"`.
   - `speakers`: `true` to split Cues on every Speaker change (default `false`).
   - `force`: `true` to replace an existing Subtitle File (default `false`; ask the user before overwriting unless they asked to replace it).
2. `create_subtitles` queues the Media File and returns the Subtitle File path immediately.
3. Poll `subtitles_status` with the returned path until `state` is `"completed"` or `"failed"`, then report the Subtitle File path, detected language, duration, and Cue count.

## Without the MCP tools (CLI fallback)

Use the `sottovoce` command in a shell (or `/Applications/Sottovoce.app/Contents/MacOS/Sottovoce`):

```sh
sottovoce "/path/to/video.mov" --style classic --format srt --json
sottovoce "/path/to/reel.mp4" --style short --words 2 --format vtt --json
```

- Pass `--force` only when the user wants to replace an existing Subtitle File.
- Progress goes to stderr; stdout prints one Subtitle File path per line, or with `--json` a JSON array of results (`mediaFile`, `subtitleFile`, `format`, `style`, `language`, `duration`, `cues`, or `error`).
- If one file fails in a multi-file command, the remaining files are still processed and the exit code is non-zero.
