import Foundation

/// Converts contiguous Ukrainian/Russian/English cardinal-number words into
/// digits before intent selection. This is a language grammar, not a command
/// phrase table; unknown or non-contiguous words remain untouched.
enum SpokenCardinalNormalizer {
    private static let values: [String: Int] = [
        "нуль":0,"ноль":0,"zero":0,"один":1,"одна":1,"одне":1,"одну":1,"раз":1,"one":1,
        "два":2,"дві":2,"две":2,"two":2,"три":3,"three":3,"чотири":4,"четыре":4,"four":4,
        "п'ять":5,"пять":5,"five":5,"шість":6,"шесть":6,"six":6,"сім":7,"семь":7,"seven":7,
        "вісім":8,"восемь":8,"eight":8,"дев'ять":9,"девять":9,"nine":9,"десять":10,"ten":10,
        "одинадцять":11,"одиннадцать":11,"eleven":11,"дванадцять":12,"двенадцать":12,"twelve":12,
        "тринадцять":13,"тринадцать":13,"thirteen":13,"чотирнадцять":14,"четырнадцать":14,
        "п'ятнадцять":15,"пятнадцать":15,"шістнадцять":16,"шестнадцать":16,"сімнадцять":17,"семнадцать":17,
        "вісімнадцять":18,"восемнадцать":18,"дев'ятнадцять":19,"девятнадцать":19,
        "двадцять":20,"двадцать":20,"twenty":20,"тридцять":30,"тридцать":30,"thirty":30,
        "сорок":40,"forty":40,"п'ятдесят":50,"пятьдесят":50,"fifty":50,"шістдесят":60,"шестьдесят":60,
        "сімдесят":70,"семьдесят":70,"вісімдесят":80,"восемьдесят":80,"дев'яносто":90,"девяносто":90,
        "сто":100,"hundred":100,"двісті":200,"двести":200,"триста":300,"чотириста":400,"четыреста":400,
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
                if let value = values[key] { subtotal += value; consumed = true; cursor += 1; continue }
                if let scale = scales[key] { total += max(1, subtotal) * scale; subtotal = 0; consumed = true; cursor += 1; continue }
                break
            }
            if consumed { output.append(String(total + subtotal)); index = cursor }
            else { output.append(words[index]); index += 1 }
        }
        return output.joined(separator: " ")
    }

    private static func canonical(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters).replacingOccurrences(of: "’", with: "'")
    }
}
