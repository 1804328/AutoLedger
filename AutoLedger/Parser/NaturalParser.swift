import Foundation

// MARK: - 解析结果

struct ParseResult {
    var amount: Decimal?
    var kind: TxKind = .expense
    var categoryID: String?
    var note: String = ""
    var date: Date = Date()
    var confidence: Double = 0
}

// MARK: - 自然语言解析器

/// 把「早餐豆浆油条 12 块」这类自由文本解析成结构化交易。
enum NaturalParser {

    private static let expenseHints = ["花", "买", "付", "消费", "支出", "交", "充", "订", "缴", "还", "转出", "用了"]
    private static let incomeHints = ["收到", "赚", "发工资", "到账", "收入", "工资", "奖金", "退款", "报销", "返现", "进账", "入账", "红包收"]

    /// 主入口
    static func parse(_ raw: String,
                      rules: [String: String] = [:],
                      categories: [Category] = Category.builtins,
                      defaultKind: TxKind = .expense,
                      now: Date = Date()) -> ParseResult {
        var result = ParseResult(date: now)
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return result }

        // 1. 日期
        result.date = DateExtractor.extract(from: text, now: now)

        // 2. 金额
        let amountHit = extractAmount(from: text)
        result.amount = amountHit.amount

        // 3. 收支方向（用完整文本判断，因为「工资」在备注里）
        result.kind = inferKind(from: text, defaultKind: defaultKind)

        // 4. 备注：去掉金额与日期表达式后的残余文本
        result.note = extractNote(from: text, amountSpan: amountHit.span)

        // 5. 分类
        let categoryText = result.note.isEmpty ? text : result.note
        if let hit = MerchantRuleEngine.match(text: categoryText, rules: rules) {
            result.categoryID = hit
            result.confidence = 0.9
        } else if let builtin = MerchantRuleEngine.matchBuiltin(categoryText) {
            result.categoryID = builtin
            result.confidence = 0.75
        } else {
            result.categoryID = nil
            result.confidence = result.amount != nil ? 0.5 : 0.2
        }

        // 分类方向纠正
        if let cid = result.categoryID,
           let cat = categories.first(where: { $0.id == cid }),
           cat.kind != result.kind {
            if let alt = categories.first(where: { $0.name == cat.name && $0.kind == result.kind }) {
                result.categoryID = alt.id
            } else {
                result.categoryID = result.kind == .expense ? "other_expense" : "other_income"
            }
        }

        return result
    }

    // MARK: 收支方向

    private static func inferKind(from text: String, defaultKind: TxKind) -> TxKind {
        let lower = text.lowercased()
        var expenseScore = 0
        var incomeScore = 0
        for h in expenseHints where lower.contains(h) { expenseScore += 1 }
        for h in incomeHints where lower.contains(h) { incomeScore += 1 }

        if text.contains("-") || text.contains("－") { expenseScore += 2 }

        if incomeScore > expenseScore { return .income }
        if expenseScore > incomeScore { return .expense }
        return defaultKind
    }

    // MARK: 金额提取

    struct AmountHit {
        var amount: Decimal?
        var span: Range<String.Index>?
    }

    /// 带单位 / 符号的金额模式（优先级从高到低）
    private static let unitPatterns: [String] = [
        #"(?:[¥￥]|RMB|rmb|人民币)\s*(\d+(?:[.,]\d{1,2})?)"#,
        #"(\d+(?:[.,]\d{1,2})?)\s*(?:元整|块钱|元|块|圆)"#,
        #"(\d+(?:\.\d+)?)\s*(?:毛|角)"#,
    ]

    /// 中文数字 + 单位
    private static let chinesePattern =
        #"([零〇一二两三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟]+)\s*(?:元整|块钱|元|块|圆)"#

    /// 纯数字兜底
    private static let plainPattern = #"(?<![\d.])(\d+(?:\.\d{1,2})?)(?![\d.])"#

    static func extractAmount(from text: String) -> AmountHit {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // 1) 带单位或货币符号
        for pattern in unitPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let m = regex.firstMatch(in: text, options: [], range: full) else { continue }
            let r = m.range(at: 1)
            guard r.location != NSNotFound else { continue }
            let numStr = ns.substring(with: r).replacingOccurrences(of: ",", with: "")
            guard let d = Decimal(string: numStr) else { continue }
            var value = d
            let matched = ns.substring(with: m.range)
            if matched.contains("毛") || matched.contains("角") {
                value = d / 10
            }
            return AmountHit(amount: value.roundedTo2, span: Range(m.range, in: text))
        }

        // 2) 中文数字 + 单位
        if let regex = try? NSRegularExpression(pattern: chinesePattern),
           let m = regex.firstMatch(in: text, options: [], range: full) {
            let r = m.range(at: 1)
            if r.location != NSNotFound {
                let cn = ns.substring(with: r)
                if let d = ChineseNumber.parse(cn) {
                    return AmountHit(amount: Decimal(d).roundedTo2, span: Range(m.range, in: text))
                }
            }
        }

        // 3) 纯数字兜底
        if let regex = try? NSRegularExpression(pattern: plainPattern),
           let m = regex.firstMatch(in: text, options: [], range: full) {
            let r = m.range(at: 1)
            if r.location != NSNotFound {
                let numStr = ns.substring(with: r).replacingOccurrences(of: ",", with: "")
                if let d = Decimal(string: numStr) {
                    return AmountHit(amount: d.roundedTo2, span: Range(m.range, in: text))
                }
            }
        }

        return AmountHit(amount: nil, span: nil)
    }

    // MARK: 备注提取

    private static let noteNoise: [String] = [
        "元整", "块钱", "元", "块", "圆", "花了", "花费", "支付", "付了", "消费",
        "买了", "一共", "总共", "合计", "共计", "价格", "金额", "用了",
    ]

    private static func extractNote(from text: String, amountSpan: Range<String.Index>?) -> String {
        var s = text

        if let span = amountSpan {
            s = s.replacingCharacters(in: span, with: " ")
        }
        s = DateExtractor.stripDateExpressions(from: s)
        for token in ["¥", "￥", "RMB", "rmb", "人民币"] {
            s = s.replacingOccurrences(of: token, with: " ")
        }
        for n in noteNoise {
            s = s.replacingOccurrences(of: n, with: " ")
        }
        let junk = CharacterSet(charactersIn: "，,。.；;：:、!！?？~～|/\\-_+=*#@()（）[]【】\"'“”‘’")
        s = s.components(separatedBy: junk).joined(separator: " ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 日期表达式提取

enum DateExtractor {

    private static let relativeMap: [(word: String, dayOffset: Int)] = [
        ("大前天", -3), ("前天", -2), ("昨天", -1),
        ("今天", 0), ("今日", 0), ("刚才", 0), ("刚刚", 0), ("现在", 0),
        ("明天", 1),
    ]

    /// 从文本中解析日期；解析不到返回 now
    static func extract(from text: String, now: Date = Date()) -> Date {
        let cal = Calendar.current

        // 1) 相对日
        for item in relativeMap where text.contains(item.word) {
            return cal.date(byAdding: .day, value: item.dayOffset, to: now) ?? now
        }

        // 2) N 天前
        if let m = firstMatch(#"(\d+)\s*天前"#, in: text), let n = Int(m.groups[0]) {
            return cal.date(byAdding: .day, value: -n, to: now) ?? now
        }

        // 3) 周X / 上周X
        if let m = firstMatch(#"(上|这|本)?(?:周|星期|礼拜)([一二三四五六日天])"#, in: text) {
            let weekdayMap: [String: Int] = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]
            if let target = weekdayMap[m.groups[1]] {
                var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                if m.groups[0] == "上" { comps.weekOfYear = (comps.weekOfYear ?? 1) - 1 }
                comps.weekday = target
                if let d = cal.date(from: comps) { return d }
            }
        }

        // 4) M月D日
        if let m = firstMatch(#"(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]"#, in: text),
           let mo = Int(m.groups[0]), let da = Int(m.groups[1]) {
            var comps = cal.dateComponents([.year], from: now)
            comps.month = mo
            comps.day = da
            if let d = cal.date(from: comps) { return d }
        }

        // 5) D号 / D日
        if let m = firstMatch(#"(?<![\d月])(\d{1,2})\s*[日号](?![\d])"#, in: text), let da = Int(m.groups[0]) {
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = da
            if let d0 = cal.date(from: comps) {
                var d = d0
                if d > now { d = cal.date(byAdding: .month, value: -1, to: d) ?? d }
                return d
            }
        }

        // 6) 时间 12:30
        if let m = firstMatch(#"(\d{1,2}):(\d{2})"#, in: text),
           let h = Int(m.groups[0]), let mi = Int(m.groups[1]) {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = h
            comps.minute = mi
            if let d = cal.date(from: comps) { return d }
        }

        return now
    }

    /// 从备注文本中剔除日期表达
    static func stripDateExpressions(from text: String) -> String {
        var s = text
        for item in relativeMap {
            s = s.replacingOccurrences(of: item.word, with: " ")
        }
        let patterns = [
            #"\d+\s*天前"#,
            #"(上|这|本)?(?:周|星期|礼拜)[一二三四五六日天]"#,
            #"\d{1,2}\s*月\s*\d{1,2}\s*[日号]"#,
            #"(?<![\d月])\d{1,2}\s*[日号](?![\d])"#,
            #"\d{1,2}:\d{2}"#,
        ]
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p) else { continue }
            let ns = s as NSString
            s = regex.stringByReplacingMatches(
                in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: " "
            )
        }
        return s
    }

    // MARK: 正则辅助

    struct RegexMatch {
        var value: String
        var groups: [String]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var groups: [String] = []
        if m.numberOfRanges > 1 {
            for i in 1..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
        }
        return RegexMatch(value: ns.substring(with: m.range), groups: groups)
    }
}
