import Foundation
import SwiftUI

// MARK: - 交易类型

enum TxKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }

    var symbol: String {
        switch self {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        }
    }
}

// MARK: - 记录来源

enum TxSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case shortcut
    case url
    case recurring
    case imported
    case screenshot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "手动"
        case .shortcut: return "快捷指令"
        case .url: return "链接"
        case .recurring: return "周期自动"
        case .imported: return "导入"
        case .screenshot: return "截图识别"
        }
    }

    var icon: String {
        switch self {
        case .manual: return "hand.tap.fill"
        case .shortcut: return "bolt.fill"
        case .url: return "link"
        case .recurring: return "arrow.triangle.2.circlepath"
        case .imported: return "square.and.arrow.down"
        case .screenshot: return "camera.viewfinder"
        }
    }
}

// MARK: - 分类

struct Category: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var icon: String
    var colorHex: String
    var kind: TxKind

    var color: Color { Color(hex: colorHex) }
}

extension Category {
    static let builtins: [Category] = [
        // 支出
        Category(id: "food", name: "餐饮", icon: "fork.knife", colorHex: "E8734A", kind: .expense),
        Category(id: "transport", name: "交通", icon: "car.fill", colorHex: "4A8FE8", kind: .expense),
        Category(id: "shopping", name: "购物", icon: "bag.fill", colorHex: "C77DFF", kind: .expense),
        Category(id: "housing", name: "居住", icon: "house.fill", colorHex: "5BA88A", kind: .expense),
        Category(id: "entertainment", name: "娱乐", icon: "gamecontroller.fill", colorHex: "F2B441", kind: .expense),
        Category(id: "medical", name: "医疗", icon: "cross.case.fill", colorHex: "E85D75", kind: .expense),
        Category(id: "education", name: "教育", icon: "book.fill", colorHex: "6C8EBF", kind: .expense),
        Category(id: "communication", name: "通讯", icon: "antenna.radiowaves.left.and.right", colorHex: "8A9BA8", kind: .expense),
        Category(id: "social", name: "人情", icon: "gift.fill", colorHex: "E86AA6", kind: .expense),
        Category(id: "other_expense", name: "其他", icon: "ellipsis.circle.fill", colorHex: "9AA5B1", kind: .expense),
        // 收入
        Category(id: "salary", name: "工资", icon: "banknote.fill", colorHex: "3FA96A", kind: .income),
        Category(id: "bonus", name: "奖金", icon: "star.fill", colorHex: "F2B441", kind: .income),
        Category(id: "refund", name: "退款", icon: "arrow.uturn.backward.circle.fill", colorHex: "4A8FE8", kind: .income),
        Category(id: "investment", name: "理财", icon: "chart.line.uptrend.xyaxis", colorHex: "3FA96A", kind: .income),
        Category(id: "parttime", name: "兼职", icon: "briefcase.fill", colorHex: "8A6CBF", kind: .income),
        Category(id: "other_income", name: "其他", icon: "ellipsis.circle.fill", colorHex: "9AA5B1", kind: .income),
    ]

    static func builtin(id: String) -> Category? {
        builtins.first { $0.id == id }
    }
}

// MARK: - 账本

struct Book: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "book.closed.fill"
    var colorHex: String = "5BA88A"
    var isDefault: Bool = false

    var color: Color { Color(hex: colorHex) }

    static let defaultBook = Book(name: "日常账本", icon: "book.closed.fill", colorHex: "5BA88A", isDefault: true)
}

// MARK: - 预算

struct Budget: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    /// nil 表示总预算
    var categoryID: String? = nil
    var monthlyLimit: Decimal
    var bookID: UUID? = nil
}

// MARK: - 周期账目

struct RecurringRule: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var title: String
    var kind: TxKind = .expense
    var amount: Decimal
    var categoryID: String
    var bookID: UUID
    var dayOfMonth: Int = 1
    var note: String = ""
    var isActive: Bool = true
    /// "yyyy-MM"
    var lastGeneratedMonth: String? = nil
}

// MARK: - 交易

struct Transaction: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var kind: TxKind
    var amount: Decimal
    var categoryID: String
    var bookID: UUID
    var note: String = ""
    var date: Date = Date()
    var source: TxSource = .manual
    var createdAt: Date = Date()
    /// 用于导入去重
    var fingerprint: String = ""

    var signedAmount: Decimal {
        kind == .expense ? -amount : amount
    }

    static func makeFingerprint(date: Date, amount: Decimal, note: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "\(f.string(from: date))|\(amount)|\(note)"
    }
}

// MARK: - 聚合结果（避免元组 KeyPath 无法编译）

struct CategoryTotal: Identifiable, Hashable {
    let category: Category
    let total: Decimal
    var id: String { category.id }
}

struct BudgetProgressItem: Identifiable, Hashable {
    let category: Category
    let spent: Decimal
    let limit: Decimal
    var id: String { category.id }

    var ratio: Double {
        guard limit > 0 else { return 0 }
        return spent.doubleValue / limit.doubleValue
    }
}

struct DayPoint: Identifiable, Hashable {
    let day: Int
    let expense: Double
    let income: Double
    var id: Int { day }
}

struct MonthPoint: Identifiable, Hashable {
    let month: Date
    let income: Double
    let expense: Double
    var id: String { Fmt.monthKey.string(from: month) }

    var shortLabel: String {
        let m = Calendar.current.component(.month, from: month)
        return "\(m)月"
    }
}

// MARK: - 格式化工具

enum Fmt {
    static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    static func money(_ d: Decimal) -> String {
        moneyFormatter.string(from: NSDecimalNumber(decimal: d)) ?? "0"
    }

    static func money(_ d: Double) -> String {
        moneyFormatter.string(from: NSNumber(value: d)) ?? "0"
    }

    static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    /// 用于 key 生成与解析，格式 yyyy-MM
    static let monthKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f
    }()
}

// MARK: - 日期扩展

extension Date {
    var monthKey: String { Fmt.monthKey.string(from: self) }
    var monthTitle: String { Fmt.monthTitle.string(from: self) }

    var startOfMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: comps) ?? self
    }

    var endOfMonth: Date {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: 1, to: startOfMonth) else { return self }
        return cal.date(byAdding: .second, value: -1, to: next) ?? next
    }

    var dayOfMonth: Int {
        Calendar.current.component(.day, from: self)
    }

    func addingMonths(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: n, to: self) ?? self
    }

    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isYesterday: Bool { Calendar.current.isDateInYesterday(self) }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    var roundedTo2: Decimal {
        var v = self
        var r = Decimal()
        NSDecimalRound(&r, &v, 2, .plain)
        return r
    }
}
