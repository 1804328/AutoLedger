import SwiftUI

// MARK: - 流水行

struct DayGroup: Identifiable {
    let date: Date
    let items: [Transaction]
    var id: Date { date }
}

struct TransactionRow: View {
    @EnvironmentObject var store: LedgerStore
    let tx: Transaction

    var body: some View {
        let cat = store.category(id: tx.categoryID)
        HStack(spacing: 12) {
            CategoryBadge(category: cat, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(cat.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if !tx.note.isEmpty {
                        Text(tx.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if tx.source != .manual {
                        Image(systemName: tx.source.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text((tx.kind == .expense ? "-" : "+") + "¥" + Fmt.money(tx.amount))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(tx.kind == .expense ? Theme.expense : Theme.income)
                Text(Fmt.dayLabel.string(from: tx.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - 流水列表

struct TransactionListView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var month = Date()
    @State private var searchText = ""
    @State private var filterKind: TxKind? = nil
    @State private var showAdd = false

    private var filtered: [Transaction] {
        var list = store.transactions(in: month)
        if let k = filterKind {
            list = list.filter { $0.kind == k }
        }
        if !searchText.isEmpty {
            list = list.filter {
                let cat = store.category(id: $0.categoryID)
                return $0.note.localizedCaseInsensitiveContains(searchText)
                    || cat.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    /// 按日分组
    private var grouped: [DayGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return dict
            .map { DayGroup(date: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    private var summary: LedgerStore.MonthSummary {
        store.summary(in: month)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                filterBar

                if filtered.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: searchText.isEmpty ? "这个月还没有记录" : "没有匹配的记录",
                        message: searchText.isEmpty ? "点右上角 + 手动记一笔，\n或者用快捷指令自动记。" : "换个关键词试试"
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(grouped) { group in
                            Section {
                                ForEach(group.items) { tx in
                                    NavigationLink {
                                        TransactionDetailView(tx: tx)
                                            .environmentObject(store)
                                    } label: {
                                        TransactionRow(tx: tx)
                                    }
                                    .listRowInsets(EdgeInsets())
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.delete(tx)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(dayTitle(group.date))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("支出 ¥" + Fmt.money(dayExpense(group.items)))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("流水")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索备注或分类")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTransactionView()
                    .environmentObject(store)
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation { month = month.addingMonths(-1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }

            VStack(spacing: 1) {
                Text(month.monthTitle)
                    .font(.headline)
                Text("支出 ¥\(Fmt.money(summary.expense)) · 收入 ¥\(Fmt.money(summary.income))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation { month = month.addingMonths(1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .disabled(month.monthKey >= Date().monthKey)
            .opacity(month.monthKey >= Date().monthKey ? 0.3 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterChip("全部", active: filterKind == nil) { filterKind = nil }
            filterChip("支出", active: filterKind == .expense) { filterKind = .expense }
            filterChip("收入", active: filterKind == .income) { filterKind = .income }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func filterChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? Color(hex: "1F2B33") : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(active ? Theme.accent : Color(.secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func dayTitle(_ date: Date) -> String {
        if date.isToday { return "今天" }
        if date.isYesterday { return "昨天" }
        return Fmt.dayLabel.string(from: date) + " " + Fmt.weekday.string(from: date)
    }

    private func dayExpense(_ items: [Transaction]) -> Decimal {
        items.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
    }
}
