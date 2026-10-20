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
                if let amt = scan.amount {
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

            categoryPicker

            Text(ocrLinePreview(scan.rawText))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let amt = scan.amount, amt > 0 {
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
            message = "没在截图里找到金额，可以在下面原始文本里确认识别到了什么"
        }
    }

    private func commit(force: Bool) {
        guard let scan, let amount = scan.amount, amount > 0 else { return }
        let cid = categoryID ?? fallbackCategory()
        let note = scan.parse.note.isEmpty
            ? String(scan.rawText.prefix(40))
            : scan.parse.note

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
