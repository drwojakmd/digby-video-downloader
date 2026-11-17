import Foundation

/// SubRip (.srt) files: read into cues and written back, keeping each cue's timing exactly.
/// Used to translate subtitles line by line on this Mac.
public enum SRT {
    public struct Cue: Sendable, Hashable {
        public var timing: String      // "00:01:02,500 --> 00:01:04,000"
        public var text: String        // one or more lines
        public init(timing: String, text: String) { self.timing = timing; self.text = text }
        /// The words alone, on one line, without formatting tags ("<i>", "{\an8}") — what a translator should see.
        public var plainText: String {
            var t = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            return t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    public static func parse(_ s: String) -> [Cue] {
        let normalised = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [Cue] = []
        for block in normalised.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
            guard let t = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let text = lines[(t + 1)...].joined(separator: "\n")
            cues.append(Cue(timing: lines[t].trimmingCharacters(in: .whitespaces), text: text))
        }
        return cues
    }

    public static func write(_ cues: [Cue]) -> String {
        cues.enumerated().map { i, c in "\(i + 1)\n\(c.timing)\n\(c.text)\n" }.joined(separator: "\n")
    }
}
