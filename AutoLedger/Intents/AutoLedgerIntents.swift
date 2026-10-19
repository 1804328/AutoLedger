import Foundation
import AppIntents
import SwiftUI

// MARK: - 收支类型 AppEnum

@available(iOS 17.0, *)
enum TxKindAppEnum: String, AppEnum {
    case expense
    case income

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "收支类型")
    }

    static var caseDisplayRepresentations: [TxKindAppEnum: DisplayRepresentation] {
        [
            .expense: DisplayRepresentation(title: "支出"),
            .income: DisplayRepresentation(title: "收入"),
        ]
    }
}

// MARK: - 快速记账 Intent（核心自动化入口）

@available(iOS 17.0, *)
struct AddTransactionIntent: AppIntent {
    static var title: LocalizedStringResource { "快速记一笔" }

    static var description: IntentDescription {
        IntentDescription(
            "用一句话记账，自动识别金额、分类和日期。例如：早餐豆浆油条 12 块",
            categoryName: "记账"
        )
    }

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "记账内容", description: "例如：早餐 12 元、打车 25、工资到账 8000")
    var text: String

    @Parameter(title: "账本名称", description: "不填则用当前账本")
    var bookName: String?

    init() {}

    init(text: String, bookName: String? = nil) {
        self.text = text
        self.bookName = bookName
    }

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$text)") {
            \.$bookName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LedgerStore.shared

        var bookID = store.activeBookID
        if let name = bookName, !name.isEmpty,
           let b = store.books.first(where: { $0.name == name }) {
            bookID = b.id
        }

        let result = NaturalParser.parse(
            text,
            rules: store.merchantRules,
            categories: store.allCategories
        )

        guard let amount = result.amount, amount > 0 else {
            return .result(dialog: IntentDialog(stringLiteral: "没听懂金额，请说清楚花了多少钱，例如「早餐 12 元」"))
        }

        let categoryID = result.categoryID
            ?? (result.kind == .expense ? "other_expense" : "other_income")

        let tx = Transaction(
            kind: result.kind,
            amount: amount,
            categoryID: categoryID,
            bookID: bookID,
            note: result.note.isEmpty ? text : result.note,
            date: result.date,
            source: .shortcut
        )
        store.add(tx)

        let cat = store.category(id: categoryID)
        let money = Fmt.money(amount)
        let dayText = result.date.isToday ? "今天" : Fmt.dayLabel.string(from: result.date)
        let dialog = "已记账：\(dayText) \(cat.name) \(result.kind.label) \(money) 元"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - 精确金额记账（自动化流程用）

@available(iOS 17.0, *)
struct AddAmountIntent: AppIntent {
    static var title: LocalizedStringResource { "记一笔指定金额" }

    static var description: IntentDescription {
        IntentDescription(
            "直接指定金额和分类记账，适合自动化流程",
            categoryName: "记账"
        )
    }

    static var openAppWhenRun: Bool { false }

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "收支类型")
    var kind: TxKindAppEnum

    @Parameter(title: "分类名称", description: "例如：餐饮、交通、购物")
    var categoryName: String?

    @Parameter(title: "备注")
    var note: String?

    init() {}

    init(amount: Double, kind: TxKindAppEnum, categoryName: String? = nil, note: String? = nil) {
        self.amount = amount
        self.kind = kind
        self.categoryName = categoryName
        self.note = note
    }

    static var parameterSummary: some ParameterSummary {
        Summary("记一笔 \(\.$kind) \(\.$amount) 元") {
            \.$categoryName
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LedgerStore.shared
        let kindValue: TxKind = (kind == .income) ? .income : .expense

        var resolvedCategory: String?
        if let cn = categoryName, !cn.isEmpty {
            if let c = store.allCategories.first(where: { $0.name == cn && $0.kind == kindValue }) {
                resolvedCategory = c.id
            } else if let c = store.allCategories.first(where: { $0.name == cn }) {
                resolvedCategory = c.id
            }
        }
        let categoryID = resolvedCategory
            ?? (kindValue == .expense ? "other_expense" : "other_income")

        let tx = Transaction(
            kind: kindValue,
            amount: Decimal(amount).roundedTo2,
            categoryID: categoryID,
            bookID: store.activeBookID,
            note: note ?? "",
            date: Date(),
            source: .shortcut
        )
        store.add(tx)

        let cat = store.category(id: categoryID)
        let dialog = "已记账：\(cat.name) \(kindValue.label) \(Fmt.money(Decimal(amount))) 元"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - 查询本月收支

@available(iOS 17.0, *)
struct MonthSummaryIntent: AppIntent {
    static var title: LocalizedStringResource { "查本月收支" }

    static var description: IntentDescription {
        IntentDescription(
            "查询本月总支出、总收入和结余",
            categoryName: "查询"
        )
    }

    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LedgerStore.shared
        let s = store.summary(in: Date())
        let dialog = "本月支出 \(Fmt.money(s.expense)) 元，收入 \(Fmt.money(s.income)) 元，结余 \(Fmt.money(s.balance)) 元，共 \(s.count) 笔。"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - App Shortcuts（免配置，装完即出现在快捷指令里）

@available(iOS 17.0, *)
struct AutoLedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: AddTransactionIntent(),
                phrases: [
                    "用 \(.applicationName) 记一笔",
                    "\(.applicationName) 记账",
                ],
                shortTitle: "记一笔",
                systemImageName: "plus.circle.fill"
            ),
            AppShortcut(
                intent: MonthSummaryIntent(),
                phrases: [
                    "用 \(.applicationName) 查本月收支",
                    "\(.applicationName) 本月花了多少",
                ],
                shortTitle: "本月收支",
                systemImageName: "chart.pie.fill"
            ),
        ]
    }
}

// MARK: - URL Scheme 处理

enum URLRouter {

    /// autoledger://add?text=早餐12元&book=日常账本
    /// autoledger://add?amount=25&kind=expense&category=交通&note=打车
    /// autoledger://summary
    @discardableResult
    static func handle(_ url: URL) -> String? {
        guard url.scheme == "autoledger" else { return nil }
        let store = LedgerStore.shared
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []

        func value(_ key: String) -> String? {
            items.first { $0.name == key }?.value
        }

        switch url.host {
        case "add":
            var bookID = store.activeBookID
            if let bn = value("book"), let b = store.books.first(where: { $0.name == bn }) {
                bookID = b.id
            }

            // 优先用自然语言 text
            if let text = value("text"), !text.isEmpty {
                let r = NaturalParser.parse(text, rules: store.merchantRules, categories: store.allCategories)
                guard let amount = r.amount, amount > 0 else { return "金额识别失败" }
                let cid = r.categoryID ?? (r.kind == .expense ? "other_expense" : "other_income")
                store.add(Transaction(
                    kind: r.kind, amount: amount, categoryID: cid,
                    bookID: bookID, note: r.note.isEmpty ? text : r.note,
                    date: r.date, source: .url
                ))
                return "已记账 \(Fmt.money(amount)) 元"
            }

            // 结构化参数
            guard let amtStr = value("amount"), let amt = Double(amtStr), amt > 0 else {
                return "缺少金额"
            }
            let kind: TxKind = (value("kind") == "income") ? .income : .expense
            var cid = kind == .expense ? "other_expense" : "other_income"
            if let cn = value("category"), !cn.isEmpty,
               let c = store.allCategories.first(where: { $0.name == cn && $0.kind == kind }) {
                cid = c.id
            }
            store.add(Transaction(
                kind: kind, amount: Decimal(amt).roundedTo2, categoryID: cid,
                bookID: bookID, note: value("note") ?? "", date: Date(), source: .url
            ))
            return "已记账 \(Fmt.money(Decimal(amt))) 元"

        case "summary":
            let s = store.summary(in: Date())
            return "本月支出 \(Fmt.money(s.expense)) 元，收入 \(Fmt.money(s.income)) 元"

        default:
            return nil
        }
    }
}
