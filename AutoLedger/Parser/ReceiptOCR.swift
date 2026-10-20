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
    }

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

    /// 一步到位：图片 → 文本 → 解析 → 用「整页最大的字」校正金额。
    static func scan(_ image: UIImage, store: LedgerStore) async -> ReceiptScan {
        let ocrLines = await lines(from: image)
        let raw = ocrLines.map(\.text).joined(separator: " ")
        var parsed = NaturalParser.parse(
            raw,
            rules: store.merchantRules,
            categories: store.allCategories
        )

        var candidates: [AmountCandidate] = []
        for line in ocrLines {
            guard let value = NaturalParser.extractAmount(from: line.text).amount, value > 0 else { continue }
            candidates.append(AmountCandidate(amount: value, height: line.height, line: line.text))
        }
        // 同一个金额常在一页里出现两次（标题栏 + 明细），按金额去重、保留字高最大的那次
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert(Fmt.money($0.amount)).inserted }
        candidates.sort { $0.height > $1.height }

        // 只有最大字确实远大于整页中位字高时才改判：
        // 「实付款 36.00」这种锚点命中本来是对的，不该被页脚一个稍大的数字推翻。
        if let hero = candidates.first, !ocrLines.isEmpty {
            let heights = ocrLines.map(\.height).sorted()
            let median = heights[heights.count / 2]
            if hero.height >= median * 1.6, hero.amount != parsed.amount {
                parsed.amount = hero.amount
            }
        }

        return ReceiptScan(rawText: raw, parse: parsed, candidates: candidates)
    }
}

/// 截图入账的一条完整结果：识别文本 + 解析出的账目 + 页面上的候选金额。
struct ReceiptScan {
    let rawText: String
    let parse: ParseResult
    /// 按字高从大到小排好、已去重，UI 上让用户一眼点中正确的那个
    let candidates: [ReceiptOCR.AmountCandidate]

    var amount: Decimal? { parse.amount }
}
