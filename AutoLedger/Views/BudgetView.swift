import SwiftUI

// MARK: - 预算

struct BudgetView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var month = Date()
    @State private var editingTotal = false
    @State private var totalText = ""
    @State private var editingCategory: Category? = nil
    @State private var categoryText = ""

    private var summary: LedgerStore.MonthSummary {
        store.summary(in: month)
    }

    private var totalBudget: Decimal {
        store.totalBudget ?? 0
    }

    private var remaining: Decimal {
        totalBudget - summary.expense
    }

    private var progress: Double {
        guard totalBudget > 0 else { return 0 }
        return min(1.0, summary.expense.doubleValue / totalBudget.doubleValue)
    }

    private var daysLeft: Int {
        let cal = Calendar.current
        let today = Date()
        if month.monthKey != today.monthKey { return 0 }
        let total = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return max(0, total - today.dayOfMonth)
    }

    private var dailyAllowance: Decimal {
        guard daysLeft > 0 else { return 0 }
        return max(0, remaining / Decimal(daysLeft))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthSelector
                    budgetHero
                    categoryBudgets
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("预算")
            .navigationBarTitleDisplayMode(.inline)
            .alert("设置月度总预算", isPresented: $editingTotal) {
                TextField("金额", text: $totalText)
                    .keyboardType(.decimalPad)
                Button("保存") {
                    let v = Decimal(string: totalText.replacingOccurrences(of: ",", with: "")) ?? 0
                    store.setTotalBudget(v > 0 ? v : nil)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("留空或填 0 表示不设预算")
            }
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                withAnimation { month = month.addingMonths(-1) }
            } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            Spacer()
            Text(month.monthTitle).font(.headline)
            Spacer()
            Button {
                withAnimation { month = month.addingMonths(1) }
            } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .disabled(month.monthKey >= Date().monthKey)
            .opacity(month.monthKey >= Date().monthKey ? 0.3 : 1)
        }
        .padding(.horizontal, 8)
    }

    // MARK: 预算主卡

    private var budgetHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("月度总预算")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    totalText = totalBudget > 0 ? Fmt.money(totalBudget) : ""
                    editingTotal = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            if totalBudget > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("¥ " + Fmt.money(summary.expense))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/ ¥" + Fmt.money(totalBudget))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // 进度条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15)).frame(height: 10)
                            Capsule()
                                .fill(progressColor.gradient)
                                .frame(width: max(6, geo.size.width * progress), height: 10)
                        }
                    }
                    .frame(height: 10)

                    HStack {
                        Text(remaining >= 0
                             ? "剩余 ¥\(Fmt.money(remaining))"
                             : "已超支 ¥\(Fmt.money(-remaining))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(remaining >= 0 ? Color(hex: "8FE0B0") : Color(hex: "FF9B85"))
                        Spacer()
                        if daysLeft > 0 && remaining > 0 {
                            Text("日均可用 ¥\(Fmt.money(dailyAllowance))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        } else if daysLeft == 0 && month.monthKey == Date().monthKey {
                            Text("本月最后一天")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
            } else {
                Button {
                    totalText = ""
                    editingTotal = true
                } label: {
                    VStack(spacing: 8) {
                        Text("还没有设置预算")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("点这里设一个月度上限，超支会提醒你")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.heroGradient)
        )
        .shadow(color: Theme.heroGradientShadow, radius: 16, x: 0, y: 8)
    }

    private var progressColor: Color {
        if progress >= 1.0 { return Color(hex: "FF6B6B") }
        if progress >= 0.85 { return Color(hex: "FFA94D") }
        return Theme.accent
    }

    // MARK: 分类预算

    private var categoryBudgets: some View {
        let list = store.budgetProgress(in: month)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("分类预算")
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(store.categories(for: .expense)) { c in
                        Button {
                            editingCategory = c
                            categoryText = store.budget(for: c.id).map { Fmt.money($0) } ?? ""
                        } label: {
                            Label(c.name, systemImage: c.icon)
                        }
                    }
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentDeep)
                }
            }

            if list.isEmpty {
                Text("给常超支的分类单独设上限，控制更精准")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(list) { item in
                    let ratio = item.ratio
                    VStack(spacing: 7) {
                        HStack(spacing: 10) {
                            CategoryBadge(category: item.category, size: 30)
                            Text(item.category.name)
                                .font(.subheadline)
                            Spacer()
                            Text("¥\(Fmt.money(item.spent)) / ¥\(Fmt.money(item.limit))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ratio >= 1 ? .red : .secondary)
                            Button {
                                editingCategory = item.category
                                categoryText = Fmt.money(item.limit)
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                                Capsule()
                                    .fill(ratio >= 1 ? Color.red : (ratio >= 0.85 ? Color.orange : item.category.color))
                                    .frame(width: max(4, geo.size.width * min(1, ratio)), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .alert(editingCategory.map { "「\($0.name)」预算" } ?? "分类预算",
               isPresented: Binding(
                get: { editingCategory != nil },
                set: { if !$0 { editingCategory = nil } }
               )) {
            TextField("金额", text: $categoryText)
                .keyboardType(.decimalPad)
            Button("保存") {
                if let c = editingCategory {
                    let v = Decimal(string: categoryText.replacingOccurrences(of: ",", with: "")) ?? 0
                    store.setBudget(categoryID: c.id, amount: v > 0 ? v : nil)
                }
                editingCategory = nil
            }
            Button("删除", role: .destructive) {
                if let c = editingCategory {
                    store.setBudget(categoryID: c.id, amount: nil)
                }
                editingCategory = nil
            }
            Button("取消", role: .cancel) { editingCategory = nil }
        } message: {
            Text("留空或填 0 表示取消这个分类的预算")
        }
    }
}
