import UIKit
import Vision

/// 支付截图取字。走系统 Vision，本机识别，不上传图片、不联网。
///
/// 输出拼成一行交给 `NaturalParser`：截图里的「2026年10月20日 14:32」和 19 位订单号
/// 会被屏蔽表跳过，「实付¥31.00」由账单锚点档命中（而不是排在更前面的优惠价或余额）。
enum ReceiptOCR {

    /// 按阅读顺序（自上而下、自左而右）返回识别出的文本行。
    /// 顺序很重要：解析器的兜底档取第一个命中，乱序就会取到别的东西。
    static func lines(from image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            // .accurate 而不是 .fast：中文小额字体、支付页艺术字，fast 的漏识率明显更高
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
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
            }.map(\.1)
        }.value
    }

    static func text(from image: UIImage) async -> String {
        (await lines(from: image)).joined(separator: " ")
    }
}

/// 截图入账的一条完整结果：识别文本 + 解析出的账目。
struct ReceiptScan {
    let rawText: String
    let parse: ParseResult

    var amount: Decimal? { parse.amount }
}

extension ReceiptOCR {

    /// 一步到位：图片 → 文本 → 解析。UI 和自动化都用它。
    static func scan(_ image: UIImage, store: LedgerStore) async -> ReceiptScan {
        let raw = await text(from: image)
        let parsed = NaturalParser.parse(
            raw,
            rules: store.merchantRules,
            categories: store.allCategories
        )
        return ReceiptScan(rawText: raw, parse: parsed)
    }
}
