<p align="center">
  <img src="plugins/sottovoce/assets/logo.png" width="128" height="128" alt="Sottovoce icon" />
</p>

# Sottovoce

A personal macOS app, CLI, and local MCP server that turns the speech in a video or audio file into clean SRT or VTT subtitle files ready to import into DaVinci Resolve, CapCut, and similar editors. Everything runs locally on Apple Silicon.

## CLI

```sh
sottovoce interview.mov                           # Classic SRT next to the video
sottovoce reel.mp4 --style short --words 2        # Short style, up to 2 words per cue
sottovoce a.mov b.mkv --format vtt --json         # VTT + JSON output for agents
sottovoce podcast.wav --speakers --translate en   # Split on speaker changes + English translation (macOS 26+)
sottovoce watch ~/Movies/Inbox                    # Subtitle every media file that lands in a folder
sottovoce mcp                                     # Local stdio MCP server (create_subtitles, subtitles_status)
```

- Progress goes to `stderr`; `stdout` prints one Subtitle File path per line (or a JSON array with `--json`).
- Existing Subtitle Files are never overwritten without `--force`.
- MKV and other containers AVFoundation cannot open are decoded with Homebrew `ffmpeg` (`brew install ffmpeg`).
- Custom terms and misheard variants live in `~/.sottovoce/vocabulary.md` (`- Term = variant, variant | description`).

## Development

```sh
./scripts/dev-link.sh                  # builds Debug Sottovoce.app and links build/sottovoce
./build/sottovoce interview.mov        # run the CLI against the Debug build
cd SottovoceCore && swift test         # domain logic tests
```

- `Sottovoce/` is the macOS app, CLI, and MCP server in one executable (ADR 0004); `SottovoceCore/` is a pure Swift package with domain logic and tests.
- Glossary in [GLOSSARY.md](GLOSSARY.md), architecture decisions in [docs/adr](docs/adr/).
- Models are borrowed from Takku or Dimmela when already downloaded (ADR 0005), or downloaded automatically at first use into `~/Library/Application Support/Sottovoce/Models`.
- Agent skill and MCP plugin manifests live in [plugins/sottovoce](plugins/sottovoce/).
