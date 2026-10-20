import SwiftUI

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .home

    enum Tab: Hashable {
        case home, list, stats, budget, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(Tab.home)

            TransactionListView()
                .tabItem { Label("流水", systemImage: "list.bullet.rectangle") }
                .tag(Tab.list)

            StatsView()
                .tabItem { Label("统计", systemImage: "chart.pie.fill") }
                .tag(Tab.stats)

            BudgetView()
                .tabItem { Label("预算", systemImage: "target") }
                .tag(Tab.budget)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .task {
            store.generateRecurringIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                store.generateRecurringIfNeeded()
            case .background:
                store.persistNow()
                store.autoBackupToDocuments()
            default:
                break
            }
        }
    }
}

// MARK: - 首页

struct HomeView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var showAdd = false
    @State private var showScan = false
    @State private var quickText = ""
    @State private var toast: String?
    @State private var showBookPicker = false
    @FocusState private var quickFocused: Bool

    private var monthSummary: LedgerStore.MonthSummary {
        store.summary(in: Date())
    }

    private var recent: [Transaction] {
        Array(store.currentTransactions.prefix(8))
    }

    private var todayTotal: Decimal {
        store.currentTransactions
            .filter { $0.date.isToday && $0.kind == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    quickInput
                    if let toast {
                        toastView(toast)
                    }
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("自动记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showBookPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.activeBook.icon)
                                .font(.caption)
                            Text(store.activeBook.name)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScan = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                    }
                }
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
            .sheet(isPresented: $showScan) {
                ReceiptScanSheet()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showBookPicker) {
                BookPickerSheet()
                    .environmentObject(store)
            }
        }
    }

    // MARK: 主视觉卡片

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月支出")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("¥ " + Fmt.money(monthSummary.expense))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Label(Fmt.monthTitle.string(from: Date()), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("今日 ¥" + Fmt.money(todayTotal))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            Divider().overlay(.white.opacity(0.15))

            HStack(spacing: 0) {
                metricCell(title: "本月收入", value: monthSummary.income, color: Color(hex: "8FE0B0"))
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 1, height: 32)
                metricCell(title: "本月结余", value: monthSummary.balance, color: Theme.accent)
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 1, height: 32)
                VStack(spacing: 3) {
                    Text("笔数")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(monthSummary.count)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.heroGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Theme.heroGradientShadow, radius: 18, x: 0, y: 10)
    }

    private func metricCell(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Text("¥" + Fmt.money(value))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 快速输入

    private var quickInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(.secondary)
                TextField("说一句就记好，例如：早餐 12 块", text: $quickText)
                    .focused($quickFocused)
                    .submitLabel(.done)
                    .onSubmit { submitQuick() }
                if !quickText.isEmpty {
                    Button {
                        quickText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            if !quickText.isEmpty {
                let preview = NaturalParser.parse(
                    quickText,
                    rules: store.merchantRules,
                    categories: store.allCategories
                )
                HStack(spacing: 8) {
                    if let amt = preview.amount {
                        chip("¥" + Fmt.money(amt), color: preview.kind == .expense ? Theme.expense : Theme.income)
                    } else {
                        chip("待识别金额", color: .secondary)
                    }
                    if let cid = preview.categoryID {
                        let c = store.category(id: cid)
                        chip(c.name, color: c.color)
                    } else {
                        chip("待分类", color: .secondary)
                    }
                    chip(preview.date.isToday ? "今天" : Fmt.dayLabel.string(from: preview.date), color: .secondary)
                    Spacer()
                    Button("记下") { submitQuick() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func submitQuick() {
        let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let r = NaturalParser.parse(text, rules: store.merchantRules, categories: store.allCategories)
        guard let amount = r.amount, amount > 0 else {
            showToast("没识别到金额，换个说法试试")
            return
        }
        let cid = r.categoryID ?? (r.kind == .expense ? "other_expense" : "other_income")
        store.add(Transaction(
            kind: r.kind, amount: amount, categoryID: cid,
            bookID: store.activeBookID,
            note: r.note.isEmpty ? text : r.note,
            date: r.date, source: .manual
        ))
        let c = store.category(id: cid)
        showToast("已记下 · \(c.name) ¥\(Fmt.money(amount))")
        quickText = ""
        quickFocused = false
    }

    private func showToast(_ msg: String) {
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { toast = nil }
        }
    }

    private func toastView(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.income)
            Text(msg)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.income.opacity(0.12))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: 最近流水

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近")
                    .font(.headline)
                Spacer()
                if !store.currentTransactions.isEmpty {
                    Text("共 \(store.currentTransactions.count) 笔")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if recent.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "还没有记录",
                    message: "在上面输入一句话就能记账，\n也可以用快捷指令自动记。"
                )
                .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { tx in
                        NavigationLink {
                            TransactionDetailView(tx: tx)
                                .environmentObject(store)
                        } label: {
                            TransactionRow(tx: tx)
                        }
                        .buttonStyle(.plain)
                        if tx.id != recent.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }
}

// MARK: - 渐变阴影辅助

extension Theme {
    static var heroGradientShadow: Color {
        Color(hex: "1F2B33").opacity(0.28)
    }
}
