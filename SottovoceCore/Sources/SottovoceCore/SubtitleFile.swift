import Foundation

/// The syntax of a Subtitle File: SRT (the default) or VTT.
public enum Format: String, CaseIterable, Sendable, Codable {
    case srt
    case vtt
}

/// Writing Cues as a Subtitle File (plain text, UTF-8 without BOM, numbered Cues, no overlaps, no
/// zero-length Cues).
public enum SubtitleFile {
    /// The Subtitle File for a Media File: next to it, same base name, with an optional language
    /// code before the extension for a Translation (`film.it.srt`).
    public static func url(for mediaFile: URL, format: Format = .srt, language: String? = nil) -> URL {
        let base = mediaFile.deletingPathExtension()
        if let language, !language.isEmpty {
            return base.appendingPathExtension(language).appendingPathExtension(format.rawValue)
        }
        return base.appendingPathExtension(format.rawValue)
    }

    /// Renders Cues in the requested Format.
    public static func render(_ cues: [Cue], format: Format) -> String {
        switch format {
        case .srt: srt(cues)
        case .vtt: vtt(cues)
        }
    }

    /// SRT: Cues numbered from 1, `HH:MM:SS,mmm --> HH:MM:SS,mmm`, a blank line after each.
    public static func srt(_ cues: [Cue]) -> String {
        format(sanitized(cues), separator: ",")
    }

    /// WebVTT: `WEBVTT` header, Cues numbered from 1, `HH:MM:SS.mmm --> HH:MM:SS.mmm`.
    public static func vtt(_ cues: [Cue]) -> String {
        let body = format(sanitized(cues), separator: ".")
        return body.isEmpty ? "WEBVTT\n" : "WEBVTT\n\n" + body
    }

    private struct Entry {
        let startMs: Int
        let endMs: Int
        let text: String
    }

    /// Removes empty or zero-length Cues and clamps overlaps at millisecond precision so the
    /// written Subtitle File always obeys its format invariants.
    private static func sanitized(_ cues: [Cue]) -> [Entry] {
        var entries: [Entry] = []
        var previousEndMs = 0
        for cue in cues {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let startMs = max(previousEndMs, milliseconds(cue.start))
            let endMs = milliseconds(cue.end)
            guard endMs > startMs else { continue }
            entries.append(Entry(startMs: startMs, endMs: endMs, text: text))
            previousEndMs = endMs
        }
        return entries
    }

    private static func format(_ entries: [Entry], separator: Character) -> String {
        entries.enumerated().map { index, entry in
            "\(index + 1)\n\(timestamp(milliseconds: entry.startMs, separator: separator)) --> \(timestamp(milliseconds: entry.endMs, separator: separator))\n\(entry.text)\n"
        }.joined(separator: "\n")
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) * 1000).rounded())
    }

    static func timestamp(_ seconds: TimeInterval, separator: Character = ",") -> String {
        timestamp(milliseconds: milliseconds(seconds), separator: separator)
    }

    private static func timestamp(milliseconds: Int, separator: Character) -> String {
        let h = milliseconds / 3_600_000
        let m = milliseconds / 60_000 % 60
        let s = milliseconds / 1000 % 60
        let ms = milliseconds % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, String(separator), ms)
    }
}
