import Foundation

/// Speech ranges from Silero VAD probabilities and filtering of stock phrases hallucinated over
/// brief noise or silence (adapted from Takku's `SegmentSignal`, `SpeechRanges`, and `Hallucination`).
public enum SpeechDetection {
    /// Silero's default of 0.5 misses a whisper; 0.4 hears it and still rejects silence and music.
    public static let threshold: Float = 0.4
    /// Silero's step in FluidAudio: 4096 samples (256 ms at 16 kHz).
    public static let frameSamples = 4096
    public static let sampleRate: Double = 16_000
    /// Margin added around each speech range so no word onset or release is cut.
    public static let padding: TimeInterval = 0.25
    /// Pauses shorter than this stay inside the range so the recognizer keeps sentence context.
    public static let maxPause: TimeInterval = 2.0

    /// One contiguous slice of 16 kHz mono samples containing speech.
    public struct SpeechRange: Equatable, Sendable {
        public let samples: Range<Int>
        /// Seconds of frames above the speech threshold inside `samples`, excluding absorbed pauses
        /// and margins.
        public let speechDuration: TimeInterval

        public init(samples: Range<Int>, speechDuration: TimeInterval) {
            self.samples = samples
            self.speechDuration = speechDuration
        }
    }

    /// Builds speech sample ranges from per-frame Silero probabilities (one per 4096 samples).
    public static func speechRanges(
        probabilities: [Float],
        totalSamples: Int,
        sampleRate: Double = sampleRate,
        threshold: Float = threshold,
        padding: TimeInterval = padding,
        maxPause: TimeInterval = maxPause
    ) -> [SpeechRange] {
        guard !probabilities.isEmpty, totalSamples > 0 else { return [] }
        let frame = frameSamples
        let padSamples = Int((padding * sampleRate).rounded())
        let maxPauseSamples = Int((maxPause * sampleRate).rounded())
        let frameDuration = Double(frame) / sampleRate

        var raw: [(lower: Int, upper: Int, speechFrames: Int)] = []
        for (index, probability) in probabilities.enumerated() where probability >= threshold {
            let start = index * frame
            guard start < totalSamples else { break }
            let end = min(totalSamples, start + frame)
            if let last = raw.last, start - last.upper < maxPauseSamples {
                raw[raw.count - 1] = (last.lower, end, last.speechFrames + 1)
            } else {
                raw.append((start, end, 1))
            }
        }

        // Apply padding and merge any ranges that touch or overlap after padding.
        var padded: [SpeechRange] = []
        for entry in raw {
            let lower = max(0, entry.lower - padSamples)
            let upper = min(totalSamples, entry.upper + padSamples)
            let duration = Double(entry.speechFrames) * frameDuration
            if let last = padded.last, lower <= last.samples.upperBound {
                padded[padded.count - 1] = SpeechRange(
                    samples: last.samples.lowerBound..<max(last.samples.upperBound, upper),
                    speechDuration: last.speechDuration + duration
                )
            } else {
                padded.append(SpeechRange(samples: lower..<upper, speechDuration: duration))
            }
        }
        return padded
    }

    /// Shifts token times from a range back into whole-Media-File time, clamping to `maxEnd` so
    /// trailing zero-padding never pushes a word past the end of the speech range.
    public static func offsetTokens(
        _ tokens: [TimedToken],
        by offset: TimeInterval,
        clampedTo maxEnd: TimeInterval
    ) -> [TimedToken] {
        tokens.map { token in
            let start = min(max(offset, offset + token.start), maxEnd)
            let end = min(max(start, offset + token.end), maxEnd)
            return TimedToken(text: token.text, start: start, end: end)
        }
    }

    /// Stock sentences recognizers make up over short noise or silence (adapted from Takku).
    private static let stockSentences: Set<String> = [
        "grazie", "grazie a tutti", "grazie mille", "grazie per la visione", "grazie per l'attenzione",
        "sottotitoli creati dalla comunità amara.org", "sottotitoli a cura di qtss",
        "thank you", "thank you very much", "thanks for watching", "thank you for watching", "you", "bye",
        "danke", "vielen dank", "danke fürs zuschauen", "untertitel der amara.org-community",
        "merci", "merci beaucoup", "merci d'avoir regardé", "sous-titres réalisés par la communauté d'amara.org",
        "sous-titres réalisés para la communauté d'amara.org",
        "gracias", "muchas gracias", "gracias por ver", "subtítulos realizados por la comunidad de amara.org",
    ]

    /// More speech than this (pauses excluded) is real speech even if it is a stock phrase.
    private static let maxHallucinationSeconds: TimeInterval = 3.0

    /// True when everything recognized in a speech range is a single stock phrase and the range
    /// had very little detected speech.
    public static func isLikelyHallucination(_ words: [Word], speechDuration: TimeInterval) -> Bool {
        guard speechDuration <= maxHallucinationSeconds else { return false }
        let text = words.map(\.text)
            .joined(separator: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return stockSentences.contains(text)
    }
}
