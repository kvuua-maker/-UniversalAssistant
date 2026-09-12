import Foundation

/// Converts contiguous Ukrainian/Russian/English cardinal-number words into
/// digits before intent selection. This is a language grammar, not a command
/// phrase table; unknown or non-contiguous words remain untouched.
enum SpokenCardinalNormalizer {
    private static let values: [String: Int] = [
        "нуль":0,"ноль":0,"zero":0,"один":1,"одна":1,"одне":1,"одну":1,"одним":1,"однією":1,"одной":1,"раз":1,"one":1,
        "два":2,"двох":2,"двом":2,"двома":2,"дві":2,"две":2,"двумя":2,"two":2,"три":3,"трьох":3,"трьом":3,"трьома":3,"тремя":3,"three":3,"чотири":4,"чотирма":4,"четырьмя":4,"четыре":4,"four":4,
        "п'ять":5,"пять":5,"п'ятьма":5,"пятью":5,"five":5,"шість":6,"шесть":6,"шістьма":6,"шестью":6,"six":6,"сім":7,"семь":7,"сімома":7,"семью":7,"seven":7,
        "вісім":8,"восемь":8,"вісьмома":8,"восьмью":8,"eight":8,"дев'ять":9,"девять":9,"дев'ятьма":9,"девятью":9,"nine":9,"десять":10,"ten":10,
        "одинадцять":11,"одиннадцать":11,"eleven":11,"дванадцять":12,"двенадцать":12,"twelve":12,
        "тринадцять":13,"тринадцать":13,"thirteen":13,"чотирнадцять":14,"четырнадцать":14,
        "п'ятнадцять":15,"пятнадцать":15,"шістнадцять":16,"шестнадцать":16,"сімнадцять":17,"семнадцать":17,
        "вісімнадцять":18,"восемнадцать":18,"дев'ятнадцять":19,"девятнадцать":19,
        "двадцять":20,"двадцятьма":20,"двадцать":20,"двадцатью":20,"twenty":20,"тридцять":30,"тридцятьма":30,"тридцать":30,"тридцатью":30,"thirty":30,
        "сорок":40,"сорока":40,"forty":40,"п'ятдесят":50,"п'ятдесятьма":50,"пятьдесят":50,"пятьюдесятью":50,"fifty":50,"шістдесят":60,"шістдесятьма":60,"шестьдесят":60,"шестьюдесятью":60,
        "сімдесят":70,"сімдесятьма":70,"семьдесят":70,"семьюдесятью":70,"вісімдесят":80,"вісімдесятьма":80,"восемьдесят":80,"восемьюдесятью":80,"дев'яносто":90,"дев'яноста":90,"девяносто":90,"девяноста":90,
        "сто":100,"сотня":100,"однієїсотні":100,"hundred":100,"двісті":200,"двохсот":200,"двомстам":200,"двести":200,"двухсот":200,"триста":300,"трьохсот":300,"тремстам":300,"трехсот":300,"чотириста":400,"чотирьохсот":400,"четыреста":400,"четырехсот":400,
        "п'ятсот":500,"пятьсот":500,"шістсот":600,"шестьсот":600,"сімсот":700,"семьсот":700,
        "вісімсот":800,"восемьсот":800,"дев'ятсот":900,"девятьсот":900
    ]
    private static let scales: [String: Int] = [
        "тисяча":1000,"тисячі":1000,"тисяч":1000,"тысяча":1000,"тысячи":1000,"тысяч":1000,"thousand":1000
    ]

    static func normalize(_ input: String) -> String {
        let words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var output: [String] = []; var index = 0
        while index < words.count {
            var cursor = index, subtotal = 0, total = 0, consumed = false
            while cursor < words.count {
                let key = canonical(words[cursor])
                if let value = numericValue(for: key) { subtotal += value; consumed = true; cursor += 1; continue }
                if let scale = scales[key] { total += max(1, subtotal) * scale; subtotal = 0; consumed = true; cursor += 1; continue }
                break
            }
            if consumed { output.append(String(total + subtotal)); index = cursor }
            else { output.append(words[index]); index += 1 }
        }
        return output.joined(separator: " ")
    }

    private static func numericValue(for word: String) -> Int? {
        if let exact = values[word] { return exact }
        let suffixes: Set<String> = ["и", "і", "ій", "ой", "ої", "ою", "ох", "ьох", "ех", "ом", "ьом", "ем", "ма", "ьма", "тьох", "тьом", "тьма"]
        for (stem, value) in inflectedStems where word.hasPrefix(stem) {
            let suffix = String(word.dropFirst(stem.count))
            if suffixes.contains(suffix) { return value }
        }
        return nil
    }

    private static let inflectedStems: [String: Int] = [
        "чотир": 4, "четыр": 4,
        "п'ят": 5, "пят": 5, "шіст": 6, "шест": 6, "сім": 7, "сем": 7,
        "вісім": 8, "восьм": 8, "дев'ят": 9, "девят": 9, "десят": 10,
        "одинадцят": 11, "одиннадцат": 11, "дванадцят": 12, "двенадцат": 12,
        "тринадцят": 13, "тринадцат": 13, "чотирнадцят": 14, "четырнадцат": 14,
        "п'ятнадцят": 15, "пятнадцат": 15, "шістнадцят": 16, "шестнадцат": 16,
        "сімнадцят": 17, "семнадцат": 17, "вісімнадцят": 18, "восемнадцат": 18,
        "дев'ятнадцят": 19, "девятнадцат": 19, "двадцят": 20, "двадцат": 20,
        "тридцят": 30, "тридцат": 30, "п'ятдесят": 50, "пятьдесят": 50,
        "шістдесят": 60, "шестьдесят": 60, "сімдесят": 70, "семьдесят": 70,
        "вісімдесят": 80, "восемьдесят": 80, "дев'яност": 90, "девяност": 90
    ]

    private static func canonical(_ word: String) -> String {
        var value = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        for apostrophe in ["’", "ʼ", "‘", "`", "\u{02BB}"] {
            value = value.replacingOccurrences(of: apostrophe, with: "'")
        }
        return value
    }
}
