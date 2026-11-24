# Sottovoce

Personal macOS app, with a CLI and an MCP server for agents, that turns the speech in a video or audio file into a subtitle file ready to import into DaVinci Resolve, CapCut and similar editors. Transcription runs on the Mac only.

## Language

### Input and output

**Media File**:
A video or audio file with at least one audio track, given to the app to be subtitled.
_Avoid_: video, source, input

**Subtitle File**:
The file the app writes for one Media File, next to it and with the same base name, in one Format.
_Avoid_: subtitles, captions, export

**Format**:
The syntax of a Subtitle File: SRT (the default) or VTT.
_Avoid_: export type, file type

**Queue**:
The ordered list of Media Files waiting to be subtitled; they are processed one at a time.
_Avoid_: batch, job list

**Watched Folder**:
A folder Sottovoce keeps an eye on, subtitling every Media File that lands in it.
_Avoid_: hot folder, inbox

### Subtitles

**Transcript**:
The words spoken in a Media File, each with its own start and end time and, when Speakers are on, who said it, in the language spoken. Cues are built from it; it is never translated.
_Avoid_: transcription, text

**Engine**:
The speech recognizer that produces the Transcript: Parakeet or Apple.
_Avoid_: model, backend, recognizer

**Speaker**:
One distinct voice in a Media File, told apart from the others without a name.
_Avoid_: voice, person, participant

**Vocabulary**:
The list of terms (names, acronyms, jargon) that speech recognition tends to get wrong, each with the variants heard instead. It applies to every Transcript.
_Avoid_: dictionary, glossary, custom words

**Cue**:
One timed entry of a Subtitle File: the text shown on screen, with its start and end time.
_Avoid_: subtitle, caption, segment

**Line**:
One row of text inside a Cue.
_Avoid_: row

**Style**:
The rule that decides how the words of the Transcript are grouped into Cues. There are two: Classic and Short.
_Avoid_: mode, preset, format

**Classic**:
The Style of films and YouTube videos: Cues of one or two Lines, split on pauses and punctuation.
_Avoid_: normal, standard, film mode

**Short**:
The Style of short-form vertical videos: Cues of one to three words, one by default.
_Avoid_: word-by-word, single-word, karaoke

**Translation**:
A second Subtitle File, next to the original, with the Classic Cues rendered in another language.
_Avoid_: translated subtitles, dub

### Ecosystem

**Sister App**:
Takku or Dimmela, the author's other apps. The three apps use each other's downloaded models instead of downloading their own.
_Avoid_: companion app, other app
