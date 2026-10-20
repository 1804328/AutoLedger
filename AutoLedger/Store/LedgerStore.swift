import Foundation
import SwiftUI
import Combine

// MARK: - 持久化载荷

struct LedgerSnapshot: Codable {
    var version: Int = 1
    var transactions: [Transaction] = []
    var books: [Book] = [Book.defaultBook]
    var budgets: [Budget] = []
    var recurringRules: [RecurringRule] = []
    var customCategories: [Category] = []
    var merchantRules: [String: String] = [:]
    var activeBookID: UUID = Book.defaultBook.id
    var didBootstrap: Bool = false
}

// MARK: - 主数据仓库

final class LedgerStore: ObservableObject {

    static let shared = LedgerStore()

    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var books: [Book] = []
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var recurringRules: [RecurringRule] = []
    @Published private(set) var customCategories: [Category] = []
    @Published private(set) var merchantRules: [String: String] = [:]
    @Published var activeBookID: UUID = Book.defaultBook.id

    private let fileName = "ledger.json"
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        load()
        autoBackupToDocuments()
    }

    // MARK: 路径

    private var storeURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("AutoLedger", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }

    // MARK: 读写

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL) else {
            bootstrap()
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let snap = try? decoder.decode(LedgerSnapshot.self, from: data) else {
            // 数据损坏：备份后重置，避免用户彻底丢失
            let backup = storeURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: storeURL, to: backup)
            bootstrap()
            return
        }

        apply(snap)
        generateRecurringIfNeeded()
    }

    private func apply(_ snap: LedgerSnapshot) {
        transactions = snap.transactions
        books = snap.books.isEmpty ? [Book.defaultBook] : snap.books
        budgets = snap.budgets
        recurringRules = snap.recurringRules
        customCategories = snap.customCategories
        merchantRules = snap.merchantRules
        activeBookID = books.contains(where: { $0.id == snap.activeBookID })
            ? snap.activeBookID
            : (books.first?.id ?? Book.defaultBook.id)
    }

    private func snapshot() -> LedgerSnapshot {
        LedgerSnapshot(
            transactions: transactions,
            books: books,
            budgets: budgets,
            recurringRules: recurringRules,
            customCategories: customCategories,
            merchantRules: merchantRules,
            activeBookID: activeBookID,
            didBootstrap: true
        )
    }

    private func bootstrap() {
        books = [Book.defaultBook]
        activeBookID = Book.defaultBook.id
        budgets = [Budget(monthlyLimit: 5000)]
        transactions = []
        recurringRules = []
        customCategories = []
        merchantRules = [:]
        persistNow()
    }

    /// 合并写盘，避免高频操作反复 IO
    func persist() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.persistNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    func persistNow() {
        let snap = snapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(snap) else { return }

        let url = storeURL
        let tmp = url.deletingLastPathComponent().appendingPathComponent("ledger.tmp.json")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 分类

    var allCategories: [Category] {
        Category.builtins + customCategories
    }

    func categories(for kind: TxKind) -> [Category] {
        allCategories.filter { $0.kind == kind }
    }

    func category(id: String) -> Category {
        allCategories.first { $0.id == id }
            ?? Category(id: id, name: "未分类", icon: "questionmark.circle.fill", colorHex: "9AA5B1", kind: .expense)
    }

    @discardableResult
    func addCategory(name: String, icon: String, colorHex: String, kind: TxKind) -> Category {
        let cid = "custom_" + String(UUID().uuidString.prefix(8))
        let c = Category(id: cid, name: name, icon: icon, colorHex: colorHex, kind: kind)
        customCategories.append(c)
        persist()
        return c
    }

    // MARK: 交易

    var activeBook: Book {
        books.first { $0.id == activeBookID } ?? books.first ?? Book.defaultBook
    }

    var currentTransactions: [Transaction] {
        transactions
            .filter { $0.bookID == activeBookID }
            .sorted { $0.date > $1.date }
    }

    func transactions(in month: Date, bookID: UUID? = nil) -> [Transaction] {
        let bid = bookID ?? activeBookID
        let key = month.monthKey
        return transactions
            .filter { $0.bookID == bid && $0.date.monthKey == key }
            .sorted { $0.date > $1.date }
    }

    @discardableResult
    func add(_ tx: Transaction, learnRule: Bool = true) -> Transaction {
        var t = tx
        if t.fingerprint.isEmpty {
            t.fingerprint = Transaction.makeFingerprint(date: t.date, amount: t.amount, note: t.note)
        }
        transactions.append(t)
        if learnRule, let keyword = MerchantRuleEngine.keywordToLearn(note: t.note, categoryID: t.categoryID) {
            setMerchantRule(keyword: keyword, categoryID: t.categoryID)
        }
        persist()
        return t
    }

    func update(_ tx: Transaction) {
        guard let idx = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[idx] = tx
        persist()
    }

    /// 命中重复的机器入账记录（同账本、同金额、60 秒内）。
    /// 只管自动化来源：连记两笔同金额是真实的人工场景（买两杯奶茶），不能吞。
    private func automatedDuplicate(of t: Transaction) -> Transaction? {
        guard t.source != .manual && t.source != .imported else { return nil }
        return transactions.first { old in
            old.bookID == t.bookID
                && old.kind == t.kind
                && old.amount == t.amount
                && abs(old.date.timeIntervalSince(t.date)) < 60
        }
    }

    /// 自动化入口专用（截图识别 / 快捷指令 / URL）。重复则跳过并返回 nil，
    /// 因为同一次消费记两笔比漏记更难被发现。
    func addAutomated(_ tx: Transaction) -> Transaction? {
        if automatedDuplicate(of: tx) != nil { return nil }
        return add(tx)
    }

    func delete(_ tx: Transaction) {
        transactions.removeAll { $0.id == tx.id }
        persist()
    }

    func delete(ids: Set<UUID>) {
        transactions.removeAll { ids.contains($0.id) }
        persist()
    }

    func exists(fingerprint: String) -> Bool {
        transactions.contains { $0.fingerprint == fingerprint }
    }

    /// 批量导入，返回 (新增数, 跳过数)
    func importTransactions(_ list: [Transaction]) -> (added: Int, skipped: Int) {
        var added = 0
        var skipped = 0
        var known = Set(transactions.map { $0.fingerprint })
        for tx in list {
            var t = tx
            if t.fingerprint.isEmpty {
                t.fingerprint = Transaction.makeFingerprint(date: t.date, amount: t.amount, note: t.note)
            }
            if known.contains(t.fingerprint) {
                skipped += 1
                continue
            }
            known.insert(t.fingerprint)
            transactions.append(t)
            added += 1
        }
        persist()
        return (added, skipped)
    }

    // MARK: 统计

    struct MonthSummary {
        var income: Decimal = 0
        var expense: Decimal = 0
        var count: Int = 0
        var balance: Decimal { income - expense }
    }

    func summary(in month: Date, bookID: UUID? = nil) -> MonthSummary {
        let list = transactions(in: month, bookID: bookID)
        var s = MonthSummary()
        s.count = list.count
        for t in list {
            if t.kind == .expense { s.expense += t.amount } else { s.income += t.amount }
        }
        return s
    }

    /// 分类聚合（按金额降序）
    func categoryBreakdown(in month: Date, kind: TxKind, bookID: UUID? = nil) -> [CategoryTotal] {
        let list = transactions(in: month, bookID: bookID).filter { $0.kind == kind }
        var map: [String: Decimal] = [:]
        for t in list {
            map[t.categoryID, default: 0] += t.amount
        }
        return map
            .map { CategoryTotal(category: category(id: $0.key), total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    /// 每日收支序列
    func dailySeries(in month: Date, bookID: UUID? = nil) -> [DayPoint] {
        let list = transactions(in: month, bookID: bookID)
        var exp: [Int: Double] = [:]
        var inc: [Int: Double] = [:]
        for t in list {
            let d = t.date.dayOfMonth
            if t.kind == .expense { exp[d, default: 0] += t.amount.doubleValue }
            else { inc[d, default: 0] += t.amount.doubleValue }
        }
        let days = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
        return (1...days).map { DayPoint(day: $0, expense: exp[$0] ?? 0, income: inc[$0] ?? 0) }
    }

    /// 近 N 个月收支
    func monthlySeries(months: Int = 6, bookID: UUID? = nil) -> [MonthPoint] {
        let now = Date()
        return (0..<months).reversed().map { offset in
            let m = now.addingMonths(-offset)
            let s = summary(in: m, bookID: bookID)
            return MonthPoint(month: m, income: s.income.doubleValue, expense: s.expense.doubleValue)
        }
    }

    // MARK: 预算

    var totalBudget: Decimal? {
        budgets.first { $0.categoryID == nil }?.monthlyLimit
    }

    func budget(for categoryID: String) -> Decimal? {
        budgets.first { $0.categoryID == categoryID }?.monthlyLimit
    }

    func setTotalBudget(_ amount: Decimal?) {
        budgets.removeAll { $0.categoryID == nil }
        if let a = amount, a > 0 {
            budgets.append(Budget(monthlyLimit: a))
        }
        persist()
    }

    func setBudget(categoryID: String, amount: Decimal?) {
        budgets.removeAll { $0.categoryID == categoryID }
        if let a = amount, a > 0 {
            budgets.append(Budget(categoryID: categoryID, monthlyLimit: a))
        }
        persist()
    }

    func budgetProgress(in month: Date, bookID: UUID? = nil) -> [BudgetProgressItem] {
        let list = transactions(in: month, bookID: bookID).filter { $0.kind == .expense }
        var spentMap: [String: Decimal] = [:]
        for t in list {
            spentMap[t.categoryID, default: 0] += t.amount
        }
        return budgets
            .compactMap { b -> BudgetProgressItem? in
                guard let cid = b.categoryID else { return nil }
                return BudgetProgressItem(
                    category: category(id: cid),
                    spent: spentMap[cid] ?? 0,
                    limit: b.monthlyLimit
                )
            }
            .sorted { $0.ratio > $1.ratio }
    }

    // MARK: 账本

    func addBook(name: String, icon: String, colorHex: String) {
        let b = Book(name: name, icon: icon, colorHex: colorHex)
        books.append(b)
        persist()
    }

    func updateBook(_ book: Book) {
        guard let idx = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[idx] = book
        persist()
    }

    func deleteBook(_ book: Book) {
        guard books.count > 1 else { return }
        books.removeAll { $0.id == book.id }
        transactions.removeAll { $0.bookID == book.id }
        recurringRules.removeAll { $0.bookID == book.id }
        if activeBookID == book.id {
            activeBookID = books.first?.id ?? Book.defaultBook.id
        }
        persist()
    }

    func switchBook(_ id: UUID) {
        guard books.contains(where: { $0.id == id }) else { return }
        activeBookID = id
        persist()
    }

    // MARK: 周期账目

    func addRule(_ rule: RecurringRule) {
        recurringRules.append(rule)
        persist()
        generateRecurringIfNeeded()
    }

    func updateRule(_ rule: RecurringRule) {
        guard let idx = recurringRules.firstIndex(where: { $0.id == rule.id }) else { return }
        recurringRules[idx] = rule
        persist()
    }

    func deleteRule(_ rule: RecurringRule) {
        recurringRules.removeAll { $0.id == rule.id }
        persist()
    }

    /// 补齐所有到期的周期账目。每次启动 / 回前台 / 新增规则都会调用。
    @discardableResult
    func generateRecurringIfNeeded() -> Int {
        let now = Date()
        let currentKey = now.monthKey
        var generated = 0
        var didChange = false

        for idx in recurringRules.indices {
            var rule = recurringRules[idx]
            guard rule.isActive else { continue }

            // 起点：上次生成月的下一个月；从未生成过则从当月开始
            var cursor: Date
            if let last = rule.lastGeneratedMonth, let lastDate = Fmt.monthKey.date(from: last) {
                cursor = lastDate.addingMonths(1)
            } else {
                cursor = now.startOfMonth
            }

            while cursor.monthKey <= currentKey {
                let key = cursor.monthKey
                let day = min(rule.dayOfMonth, daysInMonth(cursor))
                var comps = Calendar.current.dateComponents([.year, .month], from: cursor)
                comps.day = day
                guard let fireDate = Calendar.current.date(from: comps) else { break }

                if fireDate <= now {
                    let fp = "recurring|\(rule.id.uuidString)|\(key)"
                    if !exists(fingerprint: fp) {
                        let tx = Transaction(
                            kind: rule.kind,
                            amount: rule.amount,
                            categoryID: rule.categoryID,
                            bookID: rule.bookID,
                            note: rule.note.isEmpty ? rule.title : rule.note,
                            date: fireDate,
                            source: .recurring,
                            fingerprint: fp
                        )
                        transactions.append(tx)
                        generated += 1
                    }
                }
                if rule.lastGeneratedMonth != key {
                    rule.lastGeneratedMonth = key
                    didChange = true
                }
                cursor = cursor.addingMonths(1)
            }

            recurringRules[idx] = rule
        }

        if generated > 0 || didChange {
            persist()
        }
        return generated
    }

    private func daysInMonth(_ date: Date) -> Int {
        Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    // MARK: 商户规则

    func setMerchantRule(keyword: String, categoryID: String) {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count >= 2 else { return }
        merchantRules[k] = categoryID
        persist()
    }

    func removeMerchantRule(keyword: String) {
        merchantRules.removeValue(forKey: keyword)
        persist()
    }

    func ruleCategory(for text: String) -> String? {
        MerchantRuleEngine.match(text: text, rules: merchantRules)
    }

    // MARK: 备份与恢复

    /// 把当前数据另存一份到 Documents，用户可以在「文件」App 里找到。
    /// 免费签名 7 天重签会清空 App 沙盒，这份副本在重装后仍可能保留（取决于签名工具是否清 Documents），
    /// 同时也是给用户的手动备份入口。
    func autoBackupToDocuments() {
        guard !transactions.isEmpty else { return }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("AutoLedger备份", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let url = dir.appendingPathComponent("自动记账-\(df.string(from: Date())).json")

        // 同一天只写一次
        guard !fm.fileExists(atPath: url.path) else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(snapshot()) else { return }
        try? data.write(to: url, options: .atomic)

        // 只保留最近 7 份
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) {
            let sorted = files
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in sorted.dropFirst(7) {
                try? fm.removeItem(at: old)
            }
        }
    }

    /// 从 JSON 备份恢复。返回恢复的条数。
    @discardableResult
    func restore(from data: Data) -> Result<Int, RestoreError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 先尝试完整快照
        if let snap = try? decoder.decode(LedgerSnapshot.self, from: data) {
            apply(snap)
            persistNow()
            generateRecurringIfNeeded()
            return .success(snap.transactions.count)
        }

        // 再尝试纯交易数组（导出的 JSON）
        if let list = try? decoder.decode([Transaction].self, from: data) {
            var known = Set(transactions.map { $0.fingerprint })
            var added = 0
            for tx in list {
                var t = tx
                if t.fingerprint.isEmpty {
                    t.fingerprint = Transaction.makeFingerprint(date: t.date, amount: t.amount, note: t.note)
                }
                if known.contains(t.fingerprint) { continue }
                known.insert(t.fingerprint)
                transactions.append(t)
                added += 1
            }
            persistNow()
            return .success(added)
        }

        return .failure(.decodeFailed)
    }

    enum RestoreError: Error {
        case decodeFailed

        var message: String {
            switch self {
            case .decodeFailed: return "文件格式不对，请选择本 App 导出的 JSON 备份"
            }
        }
    }

    /// 导出完整快照数据（用于分享 / 备份）
    func exportSnapshotData() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try? encoder.encode(snapshot())
    }

    // MARK: 重置

    func resetAll() {
        transactions = []
        recurringRules = []
        budgets = [Budget(monthlyLimit: 5000)]
        customCategories = []
        merchantRules = [:]
        books = [Book.defaultBook]
        activeBookID = Book.defaultBook.id
        persistNow()
    }
}
