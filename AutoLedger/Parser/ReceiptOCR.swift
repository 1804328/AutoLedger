import UIKit
import Vision

/// 支付截图取字。走系统 Vision，本机识别，不上传图片、不联网。
///
/// 截图页面的难点不是「认不出字」，而是「一页里全是数字」：优惠价、账户余额、花呗额度、
/// 19 位订单号都可能被当成金额。所以这里除了取字还输出**每行的字高**——
/// 支付结果页把金额渲染成整页最大的字，字高比阅读顺序可靠。
enum ReceiptOCR {

    /// 一行识别结果 + 归一化字高（占图片高度的比例）
    struct Line {
        let text: String
        let height: CGFloat
    }

    /// 一个候选金额，来自页面上的某一行
    struct AmountCandidate: Hashable {
        let amount: Decimal
        let height: CGFloat
        let line: String
        /// 该行在识别结果里的下标，用来找紧挨金额的商户名
        let index: Int
        /// 排序用：锚点命中 + 相对字高，越大越像「真正要记的那个」
        var score: CGFloat = 0

        var isAnchorLine: Bool {
            ReceiptOCR.anchorWords.contains(where: { line.contains($0) })
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
            }.map { Line(text: $0.1, height: $0.0.height) }
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

    /// 一步到位：图片 → 文本 → 逐行取候选金额 → 按「语义 + 字高」选一个 → 校正解析结果。
    static func scan(_ image: UIImage, store: LedgerStore) async -> ReceiptScan {
        let ocrLines = await lines(from: image)
        let raw = ocrLines.map(\.text).joined(separator: " ")
        var parsed = NaturalParser.parse(
            raw,
            rules: store.merchantRules,
            categories: store.allCategories
        )

        let candidates = rank(lines: ocrLines)

        // 候选第一名比解析器的结论更可信时改判：它自己那行带账单锚点，或者字号确实压倒性最大。
        // 两个条件缺一不可 —— 只按字高会被页脚一个稍大的数字推翻，只按锚点会漏掉金额独占一屏的成功页。
        if let best = candidates.first, best.amount != parsed.amount {
            let heights = ocrLines.map(\.height).sorted()
            let median = heights.isEmpty ? 0 : heights[heights.count / 2]
            if best.isAnchorLine || best.height >= median * 1.6 {
                parsed.amount = best.amount
            }
        }

        // 截图页解析出的备注是整页噪声（一长串），既没法看，也会把商户自学习规则库污染掉。
        // 账单页的商户名就印在金额上下方，直接拿那一行当备注。
        let merchant = candidates.first.flatMap { nearestName(to: $0.index, in: ocrLines) }
        if let merchant, parsed.note.count > 20 {
            parsed.note = merchant
        }

        return ReceiptScan(rawText: raw, parse: parsed, candidates: candidates, merchant: merchant)
    }

    /// 挨着金额那一行的上/下方找商户名：不带数字、不太长、也不是字段名的中文行。
    /// 先上后下 —— 支付宝和微信都把商户名印在金额正上方。
    private static func nearestName(to index: Int, in lines: [Line]) -> String? {
        for offset in [-1, 1, -2, -3] {
            let i = index + offset
            guard i >= 0, i < lines.count else { continue }
            let t = lines[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeName(t) { return t }
        }
        return nil
    }

    private static func looksLikeName(_ t: String) -> Bool {
        guard t.count >= 2, t.count <= 14 else { return false }
        if t.contains(where: { $0.isNumber }) { return false }
        if t.contains(">") { return false }
        if pageLabels.contains(where: { t.contains($0) }) { return false }
        return hasCJK(t)
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
            // 左列标题、右列数值的版式会被 Vision 拆成两行，纯数字那行自己不带语义，
            // 屏蔽表管不到它 —— 得回头看它左边那行标题说什么。
            if !hasCJK(line.text), i > 0 {
                let label = ocrLines[i - 1].text
                if rejectWords.contains(where: { label.contains($0) }) { continue }
            }
            raw.append(AmountCandidate(amount: value, height: line.height, line: line.text, index: i))
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
            let anchored = anchorWords.contains(where: { c.line.contains($0) })
            out[i].score = relative + (anchored ? 1.2 : 0)
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
    /// 从金额上下方就近取到的商户名，取不到为 nil
    let merchant: String?

    var amount: Decimal? { parse.amount }
}
