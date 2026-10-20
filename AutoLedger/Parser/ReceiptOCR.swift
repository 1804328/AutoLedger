import UIKit
import Vision

/// 支付截图取字。走系统 Vision，本机识别，不上传图片、不联网。
///
/// 截图页面的难点不是「认不出字」，而是「一页里全是数字」：优惠价、账户余额、花呗额度、
/// 19 位订单号都可能被当成金额。所以这里除了取字还输出**每行的字高**——
/// 支付结果页把金额渲染成整页最大的字，字高比阅读顺序可靠。
enum ReceiptOCR {

    /// 一行识别结果 + 归一化字高（占图片高度的比例）+ 归一化「距顶」距离（0 = 图片上边缘）
    struct Line {
        let text: String
        let height: CGFloat
        let top: CGFloat
    }

    /// 一个候选金额，来自页面上的某一行
    struct AmountCandidate: Hashable {
        let amount: Decimal
        let height: CGFloat
        let line: String
        /// 该行在识别结果里的下标，用来找商户名
        let index: Int
        /// 判定用语义上下文：纯数字行会继承左边那行标题（"实付" / "¥52.00" 常被拆成两行）
        var context: String = ""
        var score: CGFloat = 0

        var isAnchorLine: Bool {
            ReceiptOCR.anchorWords.contains(where: { context.contains($0) })
        }
    }

    /// 这一行的数字就是金额的措辞。与 NaturalParser 的账单锚点保持同一套说法。
    static let anchorWords = [
        "实付款", "实付", "已付款", "已付", "付款金额", "支付金额", "扣款金额", "扣款", "扣费",
        "合计", "总计", "共计", "小计", "金额", "支出", "消费", "支付", "总共",
    ]

    /// 这些词所在行的数字几乎不可能是实付金额：余额、额度、优惠、订单号、支付方式。
    /// 宁可漏进候选列表让用户点，也不要把它们选成默认答案。
    static let rejectWords = [
        "余额", "额度", "可用", "积分", "优惠", "折扣", "立减", "已省", "返", "券", "红包",
        "汇率", "单价", "数量", "件数", "运费", "服务费", "评价", "评分", "库存",
        "订单", "编号", "单号", "交易", "流水", "手机", "电话", "卡号", "尾号", "验证码",
        "付款方式", "支付方式", "花呗", "信用卡", "零钱", "分期", "账单日", "还款",
        "时间", "日期", "星期", "周", "月", "年",
    ]

    /// 还没真花出去的钱。记成支出会把没付的算进账本。
    static let unpaidWords = ["待支付", "未支付", "待付款", "应付", "预计"]

    /// 手机截图顶部一定有状态栏，电量百分比常被认成一个孤零零的整数（实测 IMG_1996 的
    /// 「934」）。它没有单位也没有标题，纯数字兜底档会把它当成金额，还会挤掉真正的
    /// 大字数字让 hero 规则失效——顶部这一条裸整数只能来自状态栏。
    static let statusBarBand: CGFloat = 0.06

    /// 汇总页特征：这种页面根本没有"这一笔"的金额，自动选必然错，只能交给人点。
    static let summaryPatterns = [
        #"账单日"#, #"还款日"#, #"应还"#, #"已用额度"#, #"可用额度"#,
        #"本月支出"#, #"累计支出"#, #"月账单"#, #"共\s*\d+\s*笔"#, #"\d+\s*笔交易"#,
        #"支出排行"#, #"收支分析"#, #"支出构成"#,
    ]

    /// 字段名和状态行，不是商户名。商户名极少以这些词收尾。
    static let nameSuffixBlock = [
        "成功", "失败", "结束", "完成", "退款", "支付", "付款", "到账", "入账",
        "支出", "收入", "优惠", "立减", "余额", "额度", "积分", "时间", "日期",
        "说明", "方式", "奖励", "记录", "统计", "管理", "分类", "标签", "备注",
        "详情", "账单", "更多", "请选择", "添加", "计入", "使用", "查看", "联系",
        "收款", "编号", "单号", "总价", "金额", "数量", "件数", "运费",
    ]

    /// 一行里同时有字段名和值时的前缀（"商户 美团"），剥掉只留值
    static let fieldPrefixes = ["商户", "付款方", "收款方", "对方", "户名", "店铺", "商家", "商品", "品名"]

    /// 按阅读顺序（自上而下、自左而右）返回识别出的文本行。
    /// 顺序很重要：解析器的兜底档取第一个命中，乱序就会取到别的东西。
    static func lines(from image: UIImage) async -> [Line] {
        guard let cg = image.cgImage else { return [] }
        // 直接取 cgImage 会丢掉 UIImage 的方向信息，Vision 拿到躺着的图就基本认不出来
        let orientation = Self.cgOrientation(image.imageOrientation)

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            // .accurate 而不是 .fast：中文小额字体、支付页艺术字，fast 的漏识率明显更高
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return []
            }

            let boxes: [(CGRect, String)] = (request.results ?? []).compactMap { obs in
                guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                return (obs.boundingBox, text)
            }

            // Vision 的归一化坐标原点在左下角：midY 越大越靠上。
            // 同一行内的两个词 midY 差值很小，用 0.02 容差判定后再按 x 排。
            return boxes.sorted { a, b in
                let dy = b.0.midY - a.0.midY
                if abs(dy) > 0.02 { return dy > 0 }
                return a.0.minX < b.0.minX
            }.map { Line(text: $0.1, height: $0.0.height, top: 1 - $0.0.midY) }
        }.value
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    static func text(from image: UIImage) async -> String {
        (await lines(from: image)).map(\.text).joined(separator: " ")
    }

    /// 页面上固定存在的字段名和按钮，不是商户名。
    /// 找备注时挨着金额的那一行如果是这些，就继续往上/往下找。
    static let pageLabels = [
        "交易成功", "支付成功", "付款成功", "更多", "详情", "账单详情", "全部账单", "反馈与投诉",
        "请选择", "添加", "计入收支", "账单管理", "账单分类", "标签", "备注", "收款方全称",
        "付款方式", "支付方式", "支付时间", "商品说明", "支付奖励", "AA收款", "往来流水证明",
        "联系收款方", "查看往来记录", "使用记账本", "本月餐饮美食",
        "本月支出", "本月收入", "累计支出", "累计收入", "支出", "收入", "金额", "奖励",
        "说明", "记录", "统计", "证明", "分类", "类目", "推荐", "查看", "余额", "额度", "积分",
    ]

    /// 一步到位：图片 → 文本 → 逐行取候选金额 → 选一个 → 校正解析结果。
    static func scan(_ image: UIImage, store: LedgerStore) async -> ReceiptScan {
        // 状态栏先扔掉：它既会被纯数字兜底档当成金额，又会让真正的大字数字失去 hero 优势
        let ocrLines = (await lines(from: image)).filter { !isStatusBarNumber($0) }
        let raw = ocrLines.map(\.text).joined(separator: " ")
        var parsed = NaturalParser.parse(
            raw,
            rules: store.merchantRules,
            categories: store.allCategories
        )

        let candidates = rank(lines: ocrLines)

        // 有「主角数字」（明显比第二名大一号）就用它；没有才退回锚点 + 字高的打分。
        // 支付成功页一定有个大字金额；明细列表页全是同字号，只能靠锚点。
        var hero: AmountCandidate?
        if !candidates.isEmpty {
            let byHeight = candidates.sorted { $0.height > $1.height }
            if byHeight.count == 1 || byHeight[0].height >= byHeight[1].height * 1.5 {
                hero = byHeight[0]
            }
        }
        let best = hero ?? candidates.first
        if let best, best.amount != parsed.amount, hero != nil || best.isAnchorLine {
            parsed.amount = best.amount
        }

        // 汇总页 / 一堆同字号数字：这页没有唯一答案，自动定必错，清空让用户点
        let needsConfirmation = isSummaryPage(ocrLines) || isAmbiguous(candidates)
        if needsConfirmation, !(candidates.first?.isAnchorLine ?? false) {
            parsed.amount = nil
        }

        // 备注优先用商户名：整页噪声当备注既没法看，也会污染商户自学习规则库
        let merchant = best.flatMap { merchantName(in: ocrLines, near: $0.index) }
        if let merchant, parsed.note.count > 20 {
            parsed.note = merchant
        }

        return ReceiptScan(rawText: raw, parse: parsed, candidates: candidates,
                           merchant: merchant, needsConfirmation: needsConfirmation)
    }

    /// 前两名一样大、且都没锚点 —— 这页没有「主角数字」。
    private static func isAmbiguous(_ cands: [AmountCandidate]) -> Bool {
        guard cands.count >= 2 else { return false }
        return !cands[0].isAnchorLine && cands[0].height <= cands[1].height * 1.15
    }

    private static func isSummaryPage(_ lines: [Line]) -> Bool {
        let joined = lines.map(\.text).joined(separator: " ")
        let ns = joined as NSString
        let full = NSRange(location: 0, length: ns.length)
        return summaryPatterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: joined, options: [], range: full) != nil
        }
    }

    /// 顶部状态栏里的裸整数（电量 934 / 93%），不是金额。带 ¥ 或汉字的行不受影响。
    private static func isStatusBarNumber(_ line: Line) -> Bool {
        guard line.top < statusBarBand else { return false }
        let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = t.hasSuffix("%") ? String(t.dropLast()) : t
        return (1...4).contains(bare.count) && bare.allSatisfy { $0.isNumber }
    }

    /// 整页挑「最像商户名」的一行：字号最大者优先，同样大时取金额上方的那行。
    /// 挨着金额的常常是「实付」「神券优惠」这种字段名，所以不能只找邻居。
    private static func merchantName(in lines: [Line], near amountIndex: Int) -> String? {
        var bestHeight = CGFloat(-1)
        var bestAbove = -1
        var bestName: String?
        for (i, l) in lines.enumerated() {
            let name = stripFieldPrefix(l.text)
            guard looksLikeName(name) else { continue }
            let h = (l.height * 10_000).rounded() / 10_000
            let above = i < amountIndex ? 1 : 0
            if bestName == nil || h > bestHeight || (h == bestHeight && above > bestAbove) {
                bestHeight = h
                bestAbove = above
                bestName = name
            }
        }
        return bestName
    }

    /// "商户 美团" 这种一行里带字段名的，剥掉前缀只留值；纯字段名剥完就空了
    private static func stripFieldPrefix(_ t: String) -> String {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        for pre in fieldPrefixes where trimmed.hasPrefix(pre) {
            return String(trimmed.dropFirst(pre.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :："))
        }
        return trimmed
    }

    private static func looksLikeName(_ t: String) -> Bool {
        guard t.count >= 2, t.count <= 16 else { return false }
        if t.contains(where: { $0.isNumber }) || t.contains(">") { return false }
        if t.contains("*") { return false }   // 收款方全称「**发(个人)」是打码名，不是商户
        if pageLabels.contains(where: { t.contains($0) }) { return false }
        if anchorWords.contains(where: { t.contains($0) }) { return false }
        if rejectWords.contains(where: { t.contains($0) }) { return false }
        if nameSuffixBlock.contains(where: { t.hasSuffix($0) }) { return false }
        if hasCJK(t) { return true }
        return t.allSatisfy { $0.isLetter || " -&'".contains($0) }   // Netflix / UNIQLO 这类纯英文店名
    }

    private static func hasCJK(_ s: String) -> Bool {
        s.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil
    }

    /// 逐行提取金额，丢掉「数字肯定不是金额」的行，再按语义 + 字高打分排序。
    private static func rank(lines ocrLines: [Line]) -> [AmountCandidate] {
        var raw: [AmountCandidate] = []
        for (i, line) in ocrLines.enumerated() {
            guard let value = NaturalParser.extractAmount(from: line.text).amount, value > 0 else { continue }
            if rejectWords.contains(where: { line.text.contains($0) }) { continue }
            if unpaidWords.contains(where: { line.text.contains($0) }) { continue }
            // 左列标题、右列数值会被 Vision 拆成两行，纯数字那行自己不带语义：
            // 标题是屏蔽词就一起丢掉，标题是锚点就一起继承。
            var context = line.text
            if !hasCJK(line.text), i > 0 {
                let label = ocrLines[i - 1].text
                if rejectWords.contains(where: { label.contains($0) })
                    || unpaidWords.contains(where: { label.contains($0) }) { continue }
                context = label + " " + line.text
            }
            raw.append(AmountCandidate(amount: value, height: line.height,
                                       line: line.text, index: i, context: context))
        }

        // 同一个金额常在一页里出现两次（标题栏 + 明细），按金额去重，保留分高的那次
        var seen = Set<String>()
        var out: [AmountCandidate] = []
        for c in raw {
            guard seen.insert(Fmt.money(c.amount)).inserted else { continue }
            out.append(c)
        }

        let tallest = out.map(\.height).max() ?? 0
        for i in out.indices {
            let c = out[i]
            let relative = tallest > 0 ? c.height / tallest : 0
            out[i].score = relative + (c.isAnchorLine ? 1.2 : 0)
        }
        out.sort { $0.score > $1.score }
        return out
    }
}

/// 截图入账的一条完整结果：识别文本 + 解析出的账目 + 页面上的候选金额。
struct ReceiptScan {
    let rawText: String
    let parse: ParseResult
    /// 按「锚点 + 字高」打分排好、已去重，UI 上让用户一眼点中正确的那个
    let candidates: [ReceiptOCR.AmountCandidate]
    /// 从整页挑出的商户名，取不到为 nil
    let merchant: String?
    /// 汇总页或多笔同字号：金额没有唯一答案，必须人点一下
    let needsConfirmation: Bool

    var amount: Decimal? { parse.amount }
}
