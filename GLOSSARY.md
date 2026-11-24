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

### Subtitles

**Transcript**:
The words spoken in a Media File, each with its own start and end time, in the language spoken. Cues are built from it; it is never translated.
_Avoid_: transcription, text

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

### Ecosystem

**Sister App**:
Takku or Dimmela, the author's other apps, whose downloaded models Sottovoce uses instead of downloading its own.
_Avoid_: companion app, other app
