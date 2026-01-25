import Foundation

enum PGNParser {
    // Pre-compiled regex patterns for better performance
    private static let headerRegexCache = NSCache<NSString, NSRegularExpression>()

    static func extractHeader(from pgn: String, key: String) -> String? {
        // Check cache first
        let cacheKey = key as NSString
        let regex: NSRegularExpression
        if let cached = headerRegexCache.object(forKey: cacheKey) {
            regex = cached
        } else {
            let pattern = "\\[\(NSRegularExpression.escapedPattern(for: key))\\s+\\\"([^\\\"]*)\\\"\\]"
            guard let newRegex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            headerRegexCache.setObject(newRegex, forKey: cacheKey)
            regex = newRegex
        }

        let range = NSRange(pgn.startIndex..<pgn.endIndex, in: pgn)
        guard let match = regex.firstMatch(in: pgn, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: pgn)
        else { return nil }
        return String(pgn[valueRange])
    }

    static func extractMoves(from pgn: String) -> [String] {
        // Limit input size to prevent DoS
        guard pgn.count < 1_000_000 else { return [] }

        // Try to find moves section - either after double newline or after last header
        var movesSection: String

        // First try: split by double newline
        let parts = pgn.components(separatedBy: "\n\n")
        if parts.count > 1, let lastPart = parts.last, !lastPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            movesSection = lastPart
        } else {
            // Fallback: find content after the last header line (line ending with ])
            let lines = pgn.components(separatedBy: .newlines)
            var foundMovesStart = false
            var movesLines: [String] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    // This is a header line, skip it
                    foundMovesStart = false
                    continue
                }
                if !trimmed.isEmpty {
                    foundMovesStart = true
                }
                if foundMovesStart {
                    movesLines.append(line)
                }
            }
            movesSection = movesLines.joined(separator: " ")
        }

        var text = movesSection
        text = removePGNComments(from: text)
        text = removePGNVariations(from: text)
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = text.replacingOccurrences(of: "\t", with: " ")
        let tokens = text.split(separator: " ").map(String.init)
        var moves: [String] = []
        moves.reserveCapacity(tokens.count / 2) // Optimize array allocation
        for token in tokens {
            if token.isEmpty { continue }
            // Skip move numbers (contain a dot)
            if token.contains(".") { continue }
            // Skip result markers
            if token == "1-0" || token == "0-1" || token == "1/2-1/2" || token == "*" {
                continue
            }
            // Skip anything that looks like a header
            if token.hasPrefix("[") { continue }
            moves.append(token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return moves
    }

    /// Remove PGN comments {like this} with proper nesting support - O(n) single pass
    private static func removePGNComments(from text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var depth = 0

        for char in text {
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                result.append(char)
            }
        }
        return result
    }

    /// Remove PGN variations (like this) with proper nesting support - O(n) single pass
    private static func removePGNVariations(from text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var depth = 0

        for char in text {
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                result.append(char)
            }
        }
        return result
    }

    static func extractClockTimes(from pgn: String) -> [String] {
        let pattern = "\\[%clk\\s+([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(pgn.startIndex..<pgn.endIndex, in: pgn)
        let matches = regex.matches(in: pgn, options: [], range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: pgn) else { return nil }
            return String(pgn[valueRange])
        }
    }
}
