# Sottovoce

A small macOS app that does one thing: takes a video and generates subtitles (SRT or VTT) that import cleanly into DaVinci Resolve, CapCut and similar editors.

Status: early planning.

## Development

```sh
./scripts/dev-link.sh                  # builds Debug and links build/sottovoce
./build/sottovoce interview.mov        # writes interview.srt next to it
cd SottovoceCore && swift test         # domain logic tests
```

- `Sottovoce/` is the macOS app, which is also the CLI (ADR 0004); `SottovoceCore/` is a pure Swift package with domain logic and tests.
- Glossary in [GLOSSARY.md](GLOSSARY.md), decisions in [docs/adr](docs/adr/).
- Signing: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` for a stable identity; without it builds are signed ad hoc.
- Models: Sottovoce uses a Parakeet model already downloaded by Takku or Dimmela when there is one (ADR 0005).
