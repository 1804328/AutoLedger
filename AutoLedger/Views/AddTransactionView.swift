import SwiftUI

// MARK: - 添加 / 编辑交易

struct AddTransactionView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    /// 传入则编辑，否则新增
    var editing: Transaction? = nil

    @State private var kind: TxKind = .expense
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var categoryID: String = "food"
    @State private var bookID: UUID = Book.defaultBook.id
    @State private var showCategoryPicker = false
    @FocusState private var amountFocused: Bool

    private var amountValue: Decimal? {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let d = Decimal(string: cleaned), d > 0 else { return nil }
        return d.roundedTo2
    }

    private var currentCategories: [Category] {
        store.categories(for: kind)
    }

    private var currentCategory: Category {
        store.category(id: categoryID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    kindPicker
                    amountField
                    categoryGrid
                    detailFields
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(editing == nil ? "记一笔" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(.body.weight(.semibold))
                        .disabled(amountValue == nil)
                }
            }
            .onAppear(perform: setup)
        }
    }

    private func setup() {
        if let e = editing {
            kind = e.kind
            amountText = Fmt.money(e.amount)
            note = e.note
            date = e.date
            categoryID = e.categoryID
            bookID = e.bookID
        } else {
            bookID = store.activeBookID
            categoryID = currentCategories.first?.id ?? "other_expense"
        }
    }

    // MARK: 收支切换

    private var kindPicker: some View {
        HStack(spacing: 0) {
            ForEach([TxKind.expense, TxKind.income], id: \.self) { k in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        kind = k
                        if !currentCategories.contains(where: { $0.id == categoryID }) {
                            categoryID = store.categories(for: k).first?.id ?? categoryID
                        }
                    }
                } label: {
                    Text(k.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(kind == k ? Color(hex: "1F2B33") : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if kind == k {
                                    Capsule().fill(Theme.accent)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    // MARK: 金额

    private var amountField: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .onTapGesture { amountFocused = true }
        }
    }

    // MARK: 分类网格

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(currentCategories) { c in
                    Button {
                        categoryID = c.id
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(categoryID == c.id ? c.color : c.color.opacity(0.12))
                                Image(systemName: c.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(categoryID == c.id ? .white : c.color)
                            }
                            .frame(width: 42, height: 42)

                            Text(c.name)
                                .font(.caption2)
                                .foregroundStyle(categoryID == c.id ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .card(padding: 0)
        }
    }

    // MARK: 其他字段

    private var detailFields: some View {
        VStack(spacing: 0) {
            HStack {
                Label("备注", systemImage: "text.alignleft")
                    .font(.subheadline)
                Spacer()
                TextField("可选", text: $note)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
            }
            .padding(14)

            Divider().padding(.leading, 14)

            HStack {
                Label("日期", systemImage: "calendar")
                    .font(.subheadline)
                Spacer()
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .labelsHidden()
            }
            .padding(14)

            Divider().padding(.leading, 14)

            HStack {
                Label("账本", systemImage: "book.closed")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $bookID) {
                    ForEach(store.books) { b in
                        Text(b.name).tag(b.id)
                    }
                }
                .labelsHidden()
            }
            .padding(14)
        }
        .card(padding: 0)
    }

    // MARK: 保存

    private func save() {
        guard let amount = amountValue else { return }

        if var e = editing {
            e.kind = kind
            e.amount = amount
            e.categoryID = categoryID
            e.note = note
            e.date = date
            e.bookID = bookID
            store.update(e)
        } else {
            store.add(Transaction(
                kind: kind, amount: amount, categoryID: categoryID,
                bookID: bookID, note: note, date: date, source: .manual
            ))
        }
        dismiss()
    }
}

// MARK: - 交易详情

struct TransactionDetailView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    let tx: Transaction

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showLearnDialog = false
    @State private var learnKeyword = ""

    private var live: Transaction {
        store.transactions.first { $0.id == tx.id } ?? tx
    }

    var body: some View {
        let cat = store.category(id: live.categoryID)
        let book = store.books.first { $0.id == live.bookID }

        ScrollView {
            VStack(spacing: 18) {
                // 头部金额
                VStack(spacing: 10) {
                    CategoryBadge(category: cat, size: 56)
                    Text((live.kind == .expense ? "-" : "+") + "¥" + Fmt.money(live.amount))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(live.kind == .expense ? Theme.expense : Theme.income)
                    Text(cat.name + " · " + live.kind.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .card()

                // 明细
                VStack(spacing: 0) {
                    infoRow(icon: "text.alignleft", title: "备注", value: live.note.isEmpty ? "无" : live.note)
                    Divider().padding(.leading, 14)
                    infoRow(icon: "calendar", title: "日期", value: Fmt.fullDate.string(from: live.date) + " " + Fmt.weekday.string(from: live.date))
                    Divider().padding(.leading, 14)
                    infoRow(icon: "book.closed", title: "账本", value: book?.name ?? "未知")
                    Divider().padding(.leading, 14)
                    infoRow(icon: live.source.icon, title: "来源", value: live.source.label)
                }
                .card(padding: 0)

                // 分类学习
                if !live.note.isEmpty {
                    Button {
                        learnKeyword = live.note
                        showLearnDialog = true
                    } label: {
                        HStack {
                            Image(systemName: "brain.head.profile")
                            Text("让「\(live.note)」以后自动归到「\(cat.name)」")
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentDeep)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.accent.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("删除这笔记录")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.red.opacity(0.1))
                        )
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddTransactionView(editing: live)
                .environmentObject(store)
        }
        .alert("删除这笔记录？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.delete(live)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复")
        }
        .alert("自动分类规则", isPresented: $showLearnDialog) {
            TextField("关键词", text: $learnKeyword)
            Button("记住") {
                let k = learnKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty {
                    store.setMerchantRule(keyword: k, categoryID: live.categoryID)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("以后备注里包含这个词，就自动归到「\(cat.name)」")
        }
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}
