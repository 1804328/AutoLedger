import Foundation

/// 商户 / 关键词 -> 分类 的规则引擎。
/// 内置常用中文商户词库，并支持从用户手动修改中自学习。
enum MerchantRuleEngine {

    /// 内置词库：关键词 -> 分类 id
    static let builtinRules: [(keyword: String, categoryID: String)] = [
        // 餐饮
        ("早餐", "food"), ("午餐", "food"), ("晚餐", "food"), ("夜宵", "food"),
        ("外卖", "food"), ("饿了么", "food"), ("美团外卖", "food"), ("美团", "food"),
        ("星巴克", "food"), ("瑞幸", "food"), ("麦当劳", "food"), ("肯德基", "food"),
        ("必胜客", "food"), ("汉堡王", "food"), ("海底捞", "food"), ("西贝", "food"),
        ("喜茶", "food"), ("奈雪", "food"), ("蜜雪冰城", "food"), ("茶百道", "food"),
        ("古茗", "food"), ("库迪", "food"), ("咖啡", "food"), ("奶茶", "food"),
        ("火锅", "food"), ("烧烤", "food"), ("食堂", "food"), ("餐厅", "food"),
        ("饭店", "food"), ("便利店", "food"), ("全家", "food"), ("罗森", "food"),
        ("水果", "food"), ("超市", "food"), ("盒马", "food"), ("永辉", "food"),
        ("叮咚", "food"), ("菜市场", "food"), ("买菜", "food"), ("豆浆", "food"),
        ("油条", "food"), ("包子", "food"), ("面条", "food"), ("米饭", "food"),
        ("快餐", "food"), ("小吃", "food"), ("零食", "food"), ("饮料", "food"),

        // 交通
        ("打车", "transport"), ("滴滴", "transport"), ("出租车", "transport"),
        ("地铁", "transport"), ("公交", "transport"), ("高铁", "transport"),
        ("火车", "transport"), ("机票", "transport"), ("航班", "transport"),
        ("加油", "transport"), ("停车", "transport"), ("过路费", "transport"),
        ("共享单车", "transport"), ("哈啰", "transport"), ("青桔", "transport"),
        ("高速", "transport"), ("车费", "transport"), ("油费", "transport"),

        // 购物
        ("淘宝", "shopping"), ("天猫", "shopping"), ("京东", "shopping"),
        ("拼多多", "shopping"), ("唯品会", "shopping"), ("闲鱼", "shopping"),
        ("亚马逊", "shopping"), ("小米", "shopping"), ("优衣库", "shopping"),
        ("服装", "shopping"), ("衣服", "shopping"), ("鞋子", "shopping"),
        ("数码", "shopping"), ("电器", "shopping"), ("日用品", "shopping"),
        ("洗护", "shopping"), ("化妆品", "shopping"), ("护肤", "shopping"),
        ("购物", "shopping"), ("快递", "shopping"),

        // 居住
        ("房租", "housing"), ("租金", "housing"), ("物业", "housing"),
        ("水费", "housing"), ("电费", "housing"), ("燃气", "housing"),
        ("燃气费", "housing"), ("供暖", "housing"), ("取暖", "housing"),
        ("房贷", "housing"), ("中介费", "housing"),

        // 娱乐
        ("电影", "entertainment"), ("电影票", "entertainment"), ("ktv", "entertainment"),
        ("游戏", "entertainment"), ("steam", "entertainment"), ("psn", "entertainment"),
        ("会员", "entertainment"), ("爱奇艺", "entertainment"),
        ("腾讯视频", "entertainment"), ("优酷", "entertainment"), ("b站", "entertainment"),
        ("哔哩哔哩", "entertainment"), ("网易云", "entertainment"), ("qq音乐", "entertainment"),
        ("spotify", "entertainment"), ("netflix", "entertainment"), ("健身", "entertainment"),
        ("健身房", "entertainment"), ("旅游", "entertainment"), ("酒店", "entertainment"),
        ("门票", "entertainment"), ("演唱会", "entertainment"), ("桌游", "entertainment"),

        // 医疗
        ("医院", "medical"), ("挂号", "medical"), ("药店", "medical"),
        ("体检", "medical"), ("诊所", "medical"), ("牙科", "medical"),
        ("看病", "medical"), ("买药", "medical"),

        // 教育
        ("学费", "education"), ("培训", "education"), ("课程", "education"),
        ("买书", "education"), ("考试", "education"),
        ("报名费", "education"), ("网课", "education"), ("学而思", "education"),

        // 通讯
        ("话费", "communication"), ("流量", "communication"), ("宽带", "communication"),
        ("中国移动", "communication"), ("中国联通", "communication"), ("中国电信", "communication"),

        // 人情
        ("红包", "social"), ("份子钱", "social"), ("礼金", "social"),
        ("礼物", "social"), ("请客", "social"), ("随礼", "social"),

        // 收入
        ("工资", "salary"), ("薪水", "salary"), ("月薪", "salary"),
        ("奖金", "bonus"), ("年终奖", "bonus"), ("提成", "bonus"),
        ("退款", "refund"), ("报销", "refund"), ("返现", "refund"),
        ("利息", "investment"), ("基金", "investment"), ("股票", "investment"),
        ("分红", "investment"),
        ("兼职", "parttime"), ("稿费", "parttime"), ("外快", "parttime"),
    ]

    /// 匹配：先查用户规则（更具体、优先级高），再查内置词库
    static func match(text: String, rules: [String: String]) -> String? {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return nil }

        let userHits = rules
            .filter { lower.contains($0.key.lowercased()) }
            .sorted { $0.key.count > $1.key.count }
        if let best = userHits.first {
            return best.value
        }

        return matchBuiltin(lower)
    }

    /// 只查内置词库
    static func matchBuiltin(_ text: String) -> String? {
        let lower = text.lowercased()
        let hits = builtinRules
            .filter { lower.contains($0.keyword.lowercased()) }
            .sorted { $0.keyword.count > $1.keyword.count }
        return hits.first?.categoryID
    }

    /// 判断某条备注是否值得学习成规则，返回应学习的关键词；不值得则返回 nil。
    /// 纯函数，不触碰 store，避免 actor 隔离问题。
    static func keywordToLearn(note: String, categoryID: String) -> String? {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.count <= 20 else { return nil }

        // 若内置词库已能正确归类，无需学习
        if let builtin = matchBuiltin(text), builtin == categoryID { return nil }

        // 去掉金额、数字、常见噪声词
        var cleaned = text
        let noise = ["元", "块钱", "块", "钱", "了", "的", "今天", "昨天", "刚才",
                     "买了", "支付", "付款", "消费", "花了", "花费", "一共", "总共"]
        for n in noise {
            cleaned = cleaned.replacingOccurrences(of: n, with: "")
        }
        // 去掉数字
        cleaned = cleaned.filter { !$0.isNumber && $0 != "." && $0 != "," }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count >= 2 else { return nil }
        if cleaned.count > 8 {
            cleaned = String(cleaned.prefix(8))
        }
        return cleaned
    }
}
