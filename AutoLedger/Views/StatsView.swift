import SwiftUI
import Charts

// MARK: - 统计

struct StatsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var month = Date()
    @State private var kind: TxKind = .expense
    @State private var range: RangeMode = .month

    enum RangeMode: String, CaseIterable {
        case month = "本月"
        case trend = "趋势"
    }

    private var summary: LedgerStore.MonthSummary {
        store.summary(in: month)
    }

    private var breakdown: [CategoryTotal] {
        store.categoryBreakdown(in: month, kind: kind)
    }

    private var totalForKind: Decimal {
        breakdown.reduce(Decimal(0)) { $0 + $1.total }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthSelector
                    segmented
                    if range == .month {
                        pieSection
                        rankingSection
                    } else {
                        trendSection
                        monthlyBarSection
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
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

    private var segmented: some View {
        HStack(spacing: 8) {
            ForEach(RangeMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { range = m }
                } label: {
                    Text(m.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(range == m ? Color(hex: "1F2B33") : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if range == m { Capsule().fill(Theme.accent) }
                                else { Color.clear }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    // MARK: 饼图

    private var pieSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                kindChip("支出", .expense)
                kindChip("收入", .income)
                Spacer()
            }

            if breakdown.isEmpty {
                EmptyStateView(icon: "chart.pie", title: "暂无数据", message: "这个月还没有\(kind.label)记录")
            } else {
                ZStack {
                    Chart(breakdown) { item in
                        SectorMark(
                            angle: .value("金额", item.total.doubleValue),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(item.category.color)
                    }
                    .frame(height: 210)

                    VStack(spacing: 2) {
                        Text("合计")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("¥" + Fmt.money(totalForKind))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }

                // 图例
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(breakdown.prefix(8))) { item in
                        HStack(spacing: 6) {
                            Circle().fill(item.category.color).frame(width: 8, height: 8)
                            Text(item.category.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(percent(item.total))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func kindChip(_ title: String, _ k: TxKind) -> some View {
        Button {
            withAnimation { kind = k }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(kind == k ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(kind == k ? (k == .expense ? Theme.expense : Theme.income) : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    private func percent(_ value: Decimal) -> String {
        guard totalForKind > 0 else { return "0%" }
        let p = (value / totalForKind).doubleValue * 100
        return String(format: "%.0f%%", p)
    }

    // MARK: 排行

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类排行")
                .font(.headline)

            if breakdown.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(breakdown.enumerated()), id: \.element.id) { idx, item in
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            CategoryBadge(category: item.category, size: 30)
                            Text(item.category.name)
                                .font(.subheadline)
                            Spacer()
                            Text("¥" + Fmt.money(item.total))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(percent(item.total))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            let ratio = totalForKind > 0 ? (item.total / totalForKind).doubleValue : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill)).frame(height: 5)
                                Capsule()
                                    .fill(item.category.color)
                                    .frame(width: max(4, geo.size.width * ratio), height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    if idx < breakdown.count - 1 {
                        Divider().padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: 趋势

    private var trendSection: some View {
        let series = store.dailySeries(in: month)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("每日支出")
                    .font(.headline)
                Spacer()
                Text("支出 ¥" + Fmt.money(summary.expense))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(series) { d in
                    BarMark(
                        x: .value("日", d.day),
                        y: .value("支出", d.expense)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.expense.opacity(0.9), Theme.expense.opacity(0.5)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .cornerRadius(3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { value in
                    AxisValueLabel {
                        if let d = value.as(Int.self) {
                            Text("\(d)").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 190)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var monthlyBarSection: some View {
        let series = store.monthlySeries(months: 6)
        return VStack(alignment: .leading, spacing: 12) {
            Text("近 6 个月")
                .font(.headline)

            Chart {
                ForEach(series) { item in
                    BarMark(
                        x: .value("月", item.shortLabel),
                        y: .value("金额", item.expense)
                    )
                    .foregroundStyle(Theme.expense.gradient)
                    .position(by: .value("类型", "支出"))
                    .cornerRadius(3)

                    BarMark(
                        x: .value("月", item.shortLabel),
                        y: .value("金额", item.income)
                    )
                    .foregroundStyle(Theme.income.gradient)
                    .position(by: .value("类型", "收入"))
                    .cornerRadius(3)
                }
            }
            .chartForegroundStyleScale(["支出": Theme.expense, "收入": Theme.income])
            .frame(height: 190)

            HStack(spacing: 16) {
                legendDot(color: Theme.expense, label: "支出")
                legendDot(color: Theme.income, label: "收入")
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
