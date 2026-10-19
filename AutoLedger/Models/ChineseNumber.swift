import Foundation

/// 中文数字 / 阿拉伯数字混合解析。
/// 支持：「十二」「二十」「一百二」「两千五」「十二点五」「一百零二」
enum ChineseNumber {

    private static let digitMap: [Character: Int] = [
        "零": 0, "〇": 0, "洞": 0,
        "一": 1, "壹": 1, "幺": 1,
        "二": 2, "贰": 2, "两": 2, "俩": 2,
        "三": 3, "叁": 3,
        "四": 4, "肆": 4,
        "五": 5, "伍": 5,
        "六": 6, "陆": 6,
        "七": 7, "柒": 7,
        "八": 8, "捌": 8,
        "九": 9, "玖": 9,
    ]

    private static let unitMap: [Character: Int] = [
        "十": 10, "拾": 10,
        "百": 100, "佰": 100,
        "千": 1000, "仟": 1000,
    ]

    private static let bigUnitMap: [Character: Int] = [
        "万": 10_000, "萬": 10_000,
        "亿": 100_000_000, "億": 100_000_000,
    ]

    /// 判断一个字符串是否整体由中文数字字符组成
    static func isChineseNumeral(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        var sawNumber = false
        for ch in s {
            if digitMap[ch] != nil || unitMap[ch] != nil || bigUnitMap[ch] != nil || ch == "点" || ch == "點" {
                if digitMap[ch] != nil { sawNumber = true }
                continue
            }
            return false
        }
        return sawNumber
    }

    /// 解析中文数字，失败返回 nil
    static func parse(_ text: String) -> Double? {
        let chars = Array(text)
        guard !chars.isEmpty else { return nil }

        var total: Double = 0        // 已结算的大单位部分
        var section: Double = 0      // 当前「万/亿」段内累加
        var pending: Double = 0      // 尚未乘单位的数字
        var lastUnit: Double = 0     // 最近一次乘过的单位（用于「一百二」= 120）
        var sawZero = false
        var sawAnyNumber = false
        var decimalPart: Double? = nil
        var inDecimal = false
        var decimalScale: Double = 0.1

        for ch in chars {
            if ch == "点" || ch == "點" {
                if decimalPart == nil {
                    inDecimal = true
                    decimalPart = 0
                }
                continue
            }

            if let d = digitMap[ch] {
                if inDecimal {
                    decimalPart! += Double(d) * decimalScale
                    decimalScale /= 10
                    continue
                }
                if d == 0 {
                    sawZero = true
                    pending = 0
                } else {
                    pending = pending * 10 + Double(d)
                }
                sawAnyNumber = true
                continue
            }

            if let u = unitMap[ch] {
                if pending == 0 { pending = 1 }
                section += pending * Double(u)
                pending = 0
                lastUnit = Double(u)
                sawAnyNumber = true
                continue
            }

            if let b = bigUnitMap[ch] {
                section += pending
                if section == 0 { section = 1 }
                total += section * Double(b)
                section = 0
                pending = 0
                lastUnit = Double(b)
                sawAnyNumber = true
                continue
            }

            return nil
        }

        guard sawAnyNumber else { return nil }

        // 口语省略：一百二 = 120、两千五 = 2500、一万二 = 12000
        if pending > 0 && pending < 10 && !sawZero && lastUnit >= 100 {
            pending *= lastUnit / 10
        }

        var result = total + section + pending
        if let dp = decimalPart {
            result += dp
        }
        return result
    }
}
