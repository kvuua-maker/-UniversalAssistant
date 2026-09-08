import Foundation

/// Reconciles additive digit groups emitted by Speech before semantic framing.
/// Telephone/dial contexts stay untouched: separated phone groups represent
/// a digit sequence rather than an additive cardinal number.
enum StructuredNumberNormalizer {
    static func normalize(_ text: String) -> String {
        let folded = text.lowercased()
        let telephoneContext = ["телефон", "номер", "подзвон", "зателефон", "набер", "позвон", "call", "dial"]
            .contains(where: folded.contains)
        guard !telephoneContext,
              let regex = try? NSRegularExpression(pattern: #"(?<![\d.,])(\d{1,})\s+(\d{3})(?![\d.,])"#) else { return text }
        var value = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range(at: 0), in: value),
                  let leftRange = Range(match.range(at: 1), in: value),
                  let rightRange = Range(match.range(at: 2), in: value),
                  let left = Int(value[leftRange]), let right = Int(value[rightRange]) else { continue }
            let reconstructed: Int? = left >= 1_000 && left.isMultiple(of: 1_000)
                ? left + right
                : (left < 1_000 ? left * 1_000 + right : nil)
            if let reconstructed { value.replaceSubrange(whole, with: String(reconstructed)) }
        }
        return value
    }
}
