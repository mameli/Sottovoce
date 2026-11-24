import Foundation

/// Writing Cues as a Subtitle File.
public enum SubtitleFile {
    /// The Subtitle File for a Media File: next to it, same base name.
    public static func url(for mediaFile: URL, format: String = "srt") -> URL {
        mediaFile.deletingPathExtension().appendingPathExtension(format)
    }

    /// SRT: Cues numbered from 1, `HH:MM:SS,mmm --> HH:MM:SS,mmm`, a blank line after each.
    public static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func timestamp(_ seconds: TimeInterval, separator: Character = ",") -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let h = milliseconds / 3_600_000
        let m = milliseconds / 60_000 % 60
        let s = milliseconds / 1000 % 60
        let ms = milliseconds % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, String(separator), ms)
    }
}
