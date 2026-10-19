import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var showResetConfirm = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var showBookEditor = false
    @State private var editingBook: Book?
    @State private var showRecurringEditor = false
    @State private var editingRule: RecurringRule?
    @State private var showShortcutGuide = false
    @State private var showImporter = false
    @State private var restoreMessage: String?
    @State private var showRestoreResult = false

    var body: some View {
        NavigationStack {
            List {
                // 自动化
                Section {
                    Button {
                        showShortcutGuide = true
                    } label: {
                        HStack(spacing: 12) {
                            iconBox("bolt.fill", Color(hex: "F2B441"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自动化记账指南")
                                    .foregroundStyle(.primary)
                                Text("配置快捷指令，一句话自动入账")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("自动化")
                }

                // 周期账目
                Section {
                    ForEach(store.recurringRules) { rule in
                        Button {
                            editingRule = rule
                            showRecurringEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                iconBox("arrow.triangle.2.circlepath", Theme.income)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.title)
                                        .foregroundStyle(.primary)
                                    Text("每月 \(rule.dayOfMonth) 日 · ¥\(Fmt.money(rule.amount)) · \(store.category(id: rule.categoryID).name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !rule.isActive {
                                    Text("暂停")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { store.deleteRule(store.recurringRules[i]) }
                    }

                    Button {
                        editingRule = nil
                        showRecurringEditor = true
                    } label: {
                        Label("添加周期账目", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.accentDeep)
                    }
                } header: {
                    Text("周期自动记账")
                } footer: {
                    Text("房租、水电、会员订阅设一次，每月自动生成，完全不用管。")
                }

                // 账本
                Section {
                    ForEach(store.books) { book in
                        Button {
                            editingBook = book
                            showBookEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                iconBox(book.icon, book.color)
                                Text(book.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if book.id == store.activeBookID {
                                    Text("当前")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.accentDeep)
                                }
                            }
                        }
                        .swipeActions {
                            Button {
                                store.switchBook(book.id)
                            } label: {
                                Label("切换", systemImage: "arrow.left.arrow.right")
                            }
                            .tint(Theme.income)
                        }
                    }

                    Button {
                        editingBook = nil
                        showBookEditor = true
                    } label: {
                        Label("添加账本", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.accentDeep)
                    }
                } header: {
                    Text("账本")
                } footer: {
                    Text("左滑账本可快速切换。删除账本会同时删除其下所有记录。")
                }

                // 数据
                Section {
                    Button {
                        exportCSV()
                    } label: {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportJSON()
                    } label: {
                        Label("备份全部数据（JSON）", systemImage: "externaldrive.badge.checkmark")
                    }

                    Button {
                        showImporter = true
                    } label: {
                        Label("从备份恢复", systemImage: "arrow.down.doc")
                    }

                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("清空所有数据", systemImage: "trash")
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("共 \(store.transactions.count) 笔记录，\(store.books.count) 个账本。\n免费签名每 7 天要重签一次，重签会清空 App 数据 —— 重签后请用「从备份恢复」把数据导回来。")
                }

                // 关于
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("URL Scheme")
                        Spacer()
                        Text("autoledger://")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("数据全部保存在本机，不上传任何服务器。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShortcutGuide) {
                ShortcutGuideView()
            }
            .sheet(isPresented: $showBookEditor) {
                BookEditorSheet(book: editingBook)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showRecurringEditor) {
                RecurringEditorSheet(rule: editingRule)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("清空所有数据？", isPresented: $showResetConfirm) {
                Button("清空", role: .destructive) { store.resetAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有记录、预算、账本都会被删除，且无法恢复。建议先导出备份。")
            }
            .alert("恢复结果", isPresented: $showRestoreResult) {
                Button("好", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
    }

    // MARK: 导入恢复

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                restoreMessage = "读不到这个文件"
                showRestoreResult = true
                return
            }

            switch store.restore(from: data) {
            case .success(let n):
                restoreMessage = "已恢复 \(n) 笔记录"
            case .failure(let err):
                restoreMessage = err.message
            }
            showRestoreResult = true

        case .failure:
            restoreMessage = "选择文件失败"
            showRestoreResult = true
        }
    }

    private func iconBox(_ icon: String, _ color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.16))
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 30, height: 30)
    }

    // MARK: 导出

    private func exportCSV() {
        var lines = ["日期,类型,分类,金额,备注,账本,来源"]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.locale = Locale(identifier: "en_US_POSIX")

        for t in store.transactions.sorted(by: { $0.date < $1.date }) {
            let cat = store.category(id: t.categoryID)
            let book = store.books.first { $0.id == t.bookID }?.name ?? ""
            let note = t.note.replacingOccurrences(of: ",", with: "，")
            lines.append([
                df.string(from: t.date),
                t.kind.label,
                cat.name,
                Fmt.money(t.amount),
                note,
                book,
                t.source.label,
            ].joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n")
        // 加 BOM 让 Excel 正确识别中文
        let data = ("\u{FEFF}" + csv).data(using: .utf8)
        writeTemp(data, ext: "csv")
    }

    private func exportJSON() {
        guard let data = store.exportSnapshotData() else { return }
        writeTemp(data, ext: "json")
    }

    private func writeTemp(_ data: Data?, ext: String) {
        guard let data else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let name = "AutoLedger-\(df.string(from: Date())).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
            showExportSheet = true
        } catch {
            // ignore
        }
    }
}

// MARK: - 分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 账本编辑器

struct BookEditorSheet: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var book: Book?

    @State private var name = ""
    @State private var icon = "book.closed.fill"
    @State private var colorHex = "5BA88A"
    @State private var showDeleteConfirm = false

    private let icons = ["book.closed.fill", "house.fill", "briefcase.fill", "airplane", "heart.fill",
                         "person.2.fill", "graduationcap.fill", "cart.fill", "creditcard.fill", "star.fill"]
    private let colors = ["5BA88A", "4A8FE8", "E8734A", "C77DFF", "F2B441", "E86AA6", "3FA96A", "8A9BA8"]

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("账本名称", text: $name)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(icons, id: \.self) { i in
                            Button {
                                icon = i
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(hex: colorHex).opacity(icon == i ? 1 : 0.14))
                                    Image(systemName: i)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(icon == i ? .white : Color(hex: colorHex))
                                }
                                .frame(height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(colors, id: \.self) { c in
                            Button {
                                colorHex = c
                            } label: {
                                ZStack {
                                    Circle().fill(Color(hex: c))
                                    if colorHex == c {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if book != nil && store.books.count > 1 {
                    Section {
                        Button("删除这个账本", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(book == nil ? "添加账本" : "编辑账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(.body.weight(.semibold))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let b = book {
                    name = b.name
                    icon = b.icon
                    colorHex = b.colorHex
                }
            }
            .alert("删除账本？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    if let b = book { store.deleteBook(b) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这个账本下的所有记录也会被删除")
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if var b = book {
            b.name = trimmed
            b.icon = icon
            b.colorHex = colorHex
            store.updateBook(b)
        } else {
            store.addBook(name: trimmed, icon: icon, colorHex: colorHex)
        }
        dismiss()
    }
}

// MARK: - 账本选择

struct BookPickerSheet: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.books) { book in
                    Button {
                        store.switchBook(book.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(book.color.opacity(0.16))
                                Image(systemName: book.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(book.color)
                            }
                            .frame(width: 32, height: 32)

                            Text(book.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if book.id == store.activeBookID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accentDeep)
                            }
                        }
                    }
                }
            }
            .navigationTitle("切换账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 周期账目编辑器

struct RecurringEditorSheet: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var rule: RecurringRule?

    @State private var title = ""
    @State private var amountText = ""
    @State private var kind: TxKind = .expense
    @State private var categoryID = "housing"
    @State private var dayOfMonth = 1
    @State private var note = ""
    @State private var isActive = true

    private var amountValue: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "")
        guard let d = Decimal(string: cleaned), d > 0 else { return nil }
        return d.roundedTo2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：房租", text: $title)
                }

                Section("金额") {
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("收支类型") {
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(TxKind.expense)
                        Text("收入").tag(TxKind.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, newKind in
                        let list = store.categories(for: newKind)
                        if !list.contains(where: { $0.id == categoryID }) {
                            categoryID = list.first?.id ?? categoryID
                        }
                    }
                }

                Section("分类") {
                    Picker("分类", selection: $categoryID) {
                        ForEach(store.categories(for: kind)) { c in
                            Label(c.name, systemImage: c.icon).tag(c.id)
                        }
                    }
                }

                Section("每月几号") {
                    Picker("日期", selection: $dayOfMonth) {
                        ForEach(1...28, id: \.self) { d in
                            Text("\(d) 日").tag(d)
                        }
                    }
                }

                Section("备注") {
                    TextField("可选", text: $note)
                }

                Section {
                    Toggle("启用", isOn: $isActive)
                }
            }
            .navigationTitle(rule == nil ? "添加周期账目" : "编辑周期账目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(.body.weight(.semibold))
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amountValue == nil)
                }
            }
            .onAppear {
                if let r = rule {
                    title = r.title
                    amountText = Fmt.money(r.amount)
                    kind = r.kind
                    categoryID = r.categoryID
                    dayOfMonth = r.dayOfMonth
                    note = r.note
                    isActive = r.isActive
                }
            }
        }
    }

    private func save() {
        guard let amount = amountValue else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if var r = rule {
            r.title = trimmed
            r.amount = amount
            r.kind = kind
            r.categoryID = categoryID
            r.dayOfMonth = dayOfMonth
            r.note = note
            r.isActive = isActive
            store.updateRule(r)
        } else {
            let r = RecurringRule(
                title: trimmed,
                kind: kind,
                amount: amount,
                categoryID: categoryID,
                bookID: store.activeBookID,
                dayOfMonth: dayOfMonth,
                note: note,
                isActive: isActive
            )
            store.addRule(r)
        }
        dismiss()
    }
}
