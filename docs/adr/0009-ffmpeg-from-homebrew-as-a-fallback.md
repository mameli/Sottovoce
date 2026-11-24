# ffmpeg from Homebrew, only as a fallback

Media Files that AVFoundation cannot open (MKV above all, the usual container for films) are decoded by running the user's own `ffmpeg`, installed with Homebrew, as a separate process. Sottovoce does not bundle ffmpeg and the cask does not depend on it: bundling would mean an LGPL-only build, signed dynamic libraries and publishing its exact source, and a hard dependency would make everyone install ffmpeg for a format most never use. Without ffmpeg, such a Media File fails with "install it with `brew install ffmpeg`".

## Considered Options

- **Bundle an LGPL ffmpeg build**: works out of the box, but brings licence obligations and a larger app.
- **A Swift Matroska demuxer with AudioToolbox decoding**: no dependency, but no mature library exists and DTS would still need ffmpeg.
