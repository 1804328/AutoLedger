import SwiftUI
import PhotosUI

/// 截图入账：选一张支付截图 → 本机 Vision 取字 → NaturalParser 解析 → 确认入账。
/// 用 PhotosPicker 而不是直接读相册，是为了完全不申请相册权限。
struct ReceiptScanSheet: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var scan: ReceiptScan?
    @State private var kind: TxKind = .expense
    @State private var categoryID: String?
    @State private var isReading = false
    @State private var message: String?
    @State private var blockedByDedupe = false
    @State private var amountText = ""
    @State private var amountOverride: Decimal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pickerSection
                    if isReading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在识别截图里的文字…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .card()
                    }
                    if let scan {
                        resultSection(scan)
                    }
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.expense)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("截图入账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
    }

    // MARK: 选图

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                    Text(image == nil ? "选择支付截图" : "换一张")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.bordered)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("支付完成页截图识别率最高；账单汇总页会被当成一笔消费。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: 结果

    private func resultSection(_ scan: ReceiptScan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let amt = chosenAmount(scan) {
                    tag("¥" + Fmt.money(amt), color: kind == .expense ? Theme.expense : Theme.income)
                } else {
                    tag("没识别出金额", color: .secondary)
                }
                let cid = categoryID ?? fallbackCategory()
                let cat = store.category(id: cid)
                tag(cat.name, color: cat.color)
                tag(scan.parse.date.isToday ? "今天" : Fmt.dayLabel.string(from: scan.parse.date),
                    color: .secondary)
            }

            // 汇总页 / 一堆同字号数字：解析器故意不猜，这里得说清为什么空着
            if scan.needsConfirmation, chosenAmount(scan) == nil {
                Label("这一页没有唯一答案，点下面一个数字，或直接手动输入",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.expense)
            }

            if scan.candidates.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(scan.needsConfirmation
                         ? "这些数字里，真正花出去的是哪个："
                         : "这一页里有好几个数字，点一下真正要记的那个：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    candidateRow(scan)
                }
            }

            TextField("金额不对？手动输一个", text: $amountText)
                .keyboardType(.decimalPad)
                .font(.subheadline)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )

            categoryPicker

            VStack(alignment: .leading, spacing: 3) {
                Text("备注：\(noteText(scan))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ocrLinePreview(scan.rawText))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }

            if let amt = chosenAmount(scan), amt > 0 {
                if blockedByDedupe {
                    Button("60 秒内已有同金额记录 · 仍然入账") { commit(force: true) }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                } else {
                    Button(action: { commit(force: false) }) {
                        Text("入账")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButtonStyle()
                }
            }
        }
        .card()
    }

    /// 页面上识别到的候选金额，按字高从大到小 —— 支付页把金额画得最大，这个顺序基本就是答案顺序
    private func candidateRow(_ scan: ReceiptScan) -> some View {
        let chosen = chosenAmount(scan)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(scan.candidates.prefix(8).enumerated()), id: \.offset) { _, c in
                    Button {
                        amountText = ""
                        amountOverride = c.amount
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("¥" + Fmt.money(c.amount))
                                .font(.caption.weight(.semibold))
                            Text(c.line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .foregroundStyle(chosen == c.amount ? Color(hex: "1F2B33") : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(chosen == c.amount ? Theme.accent : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 手动输入 > 点选的候选 > 自动识别结果
    private func chosenAmount(_ scan: ReceiptScan) -> Decimal? {
        let typed = Decimal(string: amountText.trimmingCharacters(in: .whitespaces))
        if let typed, typed > 0 { return typed.roundedTo2 }
        if let amountOverride { return amountOverride }
        return scan.amount
    }

    private var categoryPicker: some View {
        Menu {
            ForEach(store.allCategories.filter { $0.kind == kind }) { c in
                Button {
                    categoryID = c.id
                } label: {
                    Label(c.name, systemImage: categoryID == c.id ? "checkmark" : c.icon)
                }
            }
            Divider()
            Button(kind == .expense ? "改成收入" : "改成支出") {
                kind = kind == .expense ? .income : .expense
                categoryID = nil
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.caption)
                Text("纠正分类")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: 动作

    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        message = nil
        blockedByDedupe = false
        amountText = ""
        amountOverride = nil
        defer { isReading = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else {
            message = "这张图读不出来，换一张试试"
            return
        }
        image = ui

        let result = await ReceiptOCR.scan(ui, store: store)
        scan = result
        kind = result.parse.kind
        categoryID = result.parse.categoryID

        if result.amount == nil {
            message = result.candidates.isEmpty
                ? "没在截图里找到数字，手动输一个金额就能入账"
                : "没法确定哪个是实付金额 —— 点下面其中一个，或直接手动输入"
        }
    }

    private func commit(force: Bool) {
        guard let scan, let amount = chosenAmount(scan), amount > 0 else { return }
        let cid = categoryID ?? fallbackCategory()
        let note = noteText(scan)

        let tx = Transaction(
            kind: kind,
            amount: amount,
            categoryID: cid,
            bookID: store.activeBookID,
            note: note,
            date: scan.parse.date,
            source: .screenshot
        )

        if force {
            store.add(tx)
            dismiss()
        } else if store.addAutomated(tx) != nil {
            dismiss()
        } else {
            // 去重拦下了，但用户可能就是真要记两笔同金额的账，所以留一条明确出口
            blockedByDedupe = true
        }
    }

    private func fallbackCategory() -> String {
        kind == .expense ? "other_expense" : "other_income"
    }

    /// 备注优先用解析器给的结果；整页噪声时退到商户名，再退到原文前 40 字
    private func noteText(_ scan: ReceiptScan) -> String {
        if !scan.parse.note.isEmpty { return scan.parse.note }
        if let m = scan.merchant { return m }
        return String(scan.rawText.prefix(40))
    }

    /// 去掉屏蔽表已经处理过的空白噪声，只给用户看关键几行
    private func ocrLinePreview(_ raw: String) -> String {
        raw.replacingOccurrences(of: "  ", with: " ")
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}
