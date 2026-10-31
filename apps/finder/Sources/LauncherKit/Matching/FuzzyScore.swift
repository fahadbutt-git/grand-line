import Foundation

/// fzf's scoring (its algorithm v2, adapted to folded bytes): every matched
/// letter scores, a letter at a word start, after a delimiter or at a camelCase
/// hump earns a bonus (the first letter's twice), letters in a row keep the
/// bonus of the run they continue, and every gap costs a little more the
/// longer it is. Higher is better.
public enum FuzzyScore {
    static let scoreMatch = 16
    static let gapStart = -3
    static let gapExtension = -1
    static let bonusBoundary: Int8 = 8
    static let bonusBoundaryWhite: Int8 = 10
    static let bonusBoundaryDelimiter: Int8 = 9
    static let bonusCamel: Int8 = 7
    static let bonusConsecutive = 4
    static let firstCharMultiplier = 2
    /// Longer texts or queries are scored greedily instead (rare: file names are short).
    static let maxCells = 64 * 1024

    /// The score of letters matched at these positions (ascending).
    static func score(_ positions: [Int], in text: FoldedText) -> Int {
        var total = 0
        var previous = -2
        var chunk: Int8 = 0
        for (k, position) in positions.enumerated() {
            let bonus = text.bonus[position]
            if k == 0 {
                total += scoreMatch + Int(bonus) * firstCharMultiplier
                chunk = bonus
            } else if position == previous + 1 {
                if bonus >= bonusBoundary { chunk = bonus }
                total += scoreMatch + max(Int(bonus), Int(chunk), bonusConsecutive)
            } else {
                let gap = position - previous - 1
                total += gapStart + gapExtension * (gap - 1) + scoreMatch + Int(bonus)
                chunk = bonus
            }
            previous = position
        }
        return total
    }

    /// A run of `length` letters from `start`: exact, prefix, word start and substring matches.
    static func contiguous(_ start: Int, length: Int, in text: FoldedText) -> Int {
        guard length > 0 else { return 0 }
        var chunk = text.bonus[start]
        var total = scoreMatch + Int(chunk) * firstCharMultiplier
        var position = start + 1
        while position < start + length {
            let bonus = text.bonus[position]
            if bonus >= bonusBoundary { chunk = bonus }
            total += scoreMatch + max(Int(bonus), Int(chunk), bonusConsecutive)
            position += 1
        }
        return total
    }

    /// The best-scoring way to find `word`'s letters in order in `text`, with
    /// the first letter at a word start. nil when there is none.
    static func best(_ word: [UInt8], in text: FoldedText) -> (score: Int, positions: [Int])? {
        let name = text.bytes
        let n = name.count, m = word.count
        guard m > 0, m <= n else { return nil }
        if n * m > maxCells { return greedy(word, in: text) }
        let none = Int.min / 4
        var cells = [Int](repeating: none, count: m * n)
        var chunks = [Int8](repeating: 0, count: m * n)
        var from = [Int](repeating: -1, count: m * n)
        var any = false
        for j in 0..<n where name[j] == word[0] && text.starts[j] {
            cells[j] = scoreMatch + Int(text.bonus[j]) * firstCharMultiplier
            chunks[j] = text.bonus[j]
            any = true
        }
        guard any else { return nil }
        if m > 1 {
            for i in 1..<m {
                let row = i * n, above = (i - 1) * n
                var gapBest = none
                var gapFrom = -1
                var reached = false
                for j in i..<n {
                    if j >= 2 {
                        let opened = cells[above + j - 2] == none ? none : cells[above + j - 2] + gapStart
                        let extended = gapBest == none ? none : gapBest + gapExtension
                        if opened >= extended, opened != none {
                            gapBest = opened
                            gapFrom = j - 2
                        } else {
                            gapBest = extended
                        }
                    }
                    guard name[j] == word[i] else { continue }
                    let bonus = text.bonus[j]
                    var best = none, pick = -1
                    var chunk = bonus
                    let previous = cells[above + j - 1]
                    if previous != none {
                        var run = chunks[above + j - 1]
                        if bonus >= bonusBoundary { run = bonus }
                        best = previous + scoreMatch + max(Int(bonus), Int(run), bonusConsecutive)
                        pick = j - 1
                        chunk = run
                    }
                    if gapBest != none, gapBest + scoreMatch + Int(bonus) > best {
                        best = gapBest + scoreMatch + Int(bonus)
                        pick = gapFrom
                        chunk = bonus
                    }
                    guard pick >= 0 else { continue }
                    cells[row + j] = best
                    chunks[row + j] = chunk
                    from[row + j] = pick
                    reached = true
                }
                if !reached { return nil }
            }
        }
        let last = (m - 1) * n
        var end = -1
        var top = none
        for j in (m - 1)..<n where cells[last + j] > top {
            top = cells[last + j]
            end = j
        }
        guard end >= 0 else { return nil }
        var positions = [Int](repeating: 0, count: m)
        var j = end
        for i in stride(from: m - 1, through: 0, by: -1) {
            positions[i] = j
            if i > 0 { j = from[i * n + j] }
        }
        return (top, positions)
    }

    /// For very long texts: the first word start that leads, then each next letter
    /// as early as possible. Scored the same way.
    static func greedy(_ word: [UInt8], in text: FoldedText) -> (score: Int, positions: [Int])? {
        let name = text.bytes
        var start = 0
        while start < name.count {
            if name[start] == word[0], text.starts[start] {
                var positions = [start]
                var cursor = start + 1
                for letter in word.dropFirst() {
                    while cursor < name.count, name[cursor] != letter { cursor += 1 }
                    guard cursor < name.count else { return nil }
                    positions.append(cursor)
                    cursor += 1
                }
                return (score(positions, in: text), positions)
            }
            start += 1
        }
        return nil
    }
}
