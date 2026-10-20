"""ReceiptOCR 候选金额选择逻辑的 Python 忠实移植（不含打印，供用例集调用）。

对位 Swift：AutoLedger/Parser/ReceiptOCR.swift 的 rank / nearestName / scan 判定部分。
这里证的是语义与顺序，证不了 Swift 语法，也证不了 Vision 真实认字结果。
lines 的每个元素是 (文本, 归一化字高)，对应 Vision 的一个 observation。
"""
import re
from datetime import date, timedelta

ANCHOR_WORDS = [
    "实付款", "实付", "已付款", "已付", "付款金额", "支付金额", "扣款金额", "扣款", "扣费",
    "合计", "总计", "共计", "小计", "金额", "支出", "消费", "支付", "总共",
]
REJECT_WORDS = [
    "余额", "额度", "可用", "积分", "优惠", "折扣", "立减", "已省", "返", "券", "红包",
    "汇率", "单价", "数量", "件数", "运费", "服务费", "评价", "评分", "库存",
    "订单", "编号", "单号", "交易", "流水", "手机", "电话", "卡号", "尾号", "验证码",
    "付款方式", "支付方式", "花呗", "信用卡", "零钱", "分期", "账单日", "还款",
    "时间", "日期", "星期", "周", "月", "年",
]
PAGE_LABELS = [
    "交易成功", "支付成功", "付款成功", "更多", "详情", "账单详情", "全部账单", "反馈与投诉",
    "请选择", "添加", "计入收支", "账单管理", "账单分类", "标签", "备注", "收款方全称",
    "付款方式", "支付方式", "支付时间", "商品说明", "支付奖励", "AA收款", "往来流水证明",
    "联系收款方", "查看往来记录", "使用记账本", "本月餐饮美食",
    "本月支出", "本月收入", "累计支出", "累计收入", "支出", "收入", "金额", "奖励",
    "说明", "记录", "统计", "证明", "分类", "类目", "推荐", "查看", "余额", "额度", "积分",
]
# 汇总/列表页特征：这种页面没有"这一笔"的金额，自动选必然错
SUMMARY_PATTERNS = [r"账单日", r"还款日", r"应还", r"已用额度", r"可用额度", r"本月支出",
                    r"累计支出", r"月账单", r"共\s*\d+\s*笔", r"\d+\s*笔交易",
                    r"支出排行", r"收支分析", r"支出构成"]
# 状态行和字段名，不是商户名。商户名极少以这些词收尾。
NAME_SUFFIX_BLOCK = ["成功", "失败", "结束", "完成", "退款", "支付", "付款", "到账", "入账",
                     "支出", "收入", "优惠", "立减", "余额", "额度", "积分", "时间", "日期",
                     "说明", "方式", "奖励", "记录", "统计", "管理", "分类", "标签", "备注",
                     "详情", "账单", "更多", "请选择", "添加", "计入", "使用", "查看", "联系",
                     "收款", "编号", "单号", "总价", "金额", "数量", "件数", "运费"]
# 还没真花出去的钱
UNPAID_WORDS = ["待支付", "未支付", "应付", "预计", "待付款"]
# 对位 ReceiptOCR.statusBarBand：手机截图顶部那条状态栏（电量常被认成一个裸整数）
STATUS_BAR_BAND = 0.06
# 决定「这页有没有唯一主角数字」的两个比例，Swift 里是写在表达式里的字面量
HERO_RATIO = 1.5
AMBIG_RATIO = 1.15
# 对位 Swift: score = relative + (isAnchorLine ? 1.2 : 0)
ANCHOR_WEIGHT = 1.2

ABS_DATE = re.compile(r"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})[日号]?(?:\s*(\d{1,2}):(\d{2}))?")
CJK = re.compile(r"[一-鿿]")


def money(v):
    return f"{v:.2f}"


def has_cjk(t):
    return CJK.search(t) is not None


def line_top(line):
    """这行距图片顶部的归一化距离。老用例只写 (文本, 字高)，没位置就返回 None。"""
    return line[2] if len(line) > 2 else None


def is_status_bar_number(line):
    """顶部状态栏那种 1~4 位裸整数（电量常被认成「934」）。带货币符或汉字的行不受影响。"""
    top = line_top(line)
    if top is None or top >= STATUS_BAR_BAND:
        return False
    t = line[0].strip()
    bare = t[:-1] if t.endswith("%") else t
    return 1 <= len(bare) <= 4 and bare.isdigit()


def drop_status(lines):
    """状态栏那行既会被纯数字兜底档当成金额，又会让真正的大字数字失去 hero 优势，先扔掉。"""
    return [l for l in lines if not is_status_bar_number(l)]


FIELD_PREFIXES = ["商户", "付款方", "收款方", "对方", "户名", "店铺", "商家", "商品", "品名"]


def strip_field_prefix(t):
    """"商户 美团" 这种一行里带字段名的，剥掉前缀只留值；纯字段名剥完就空了。"""
    t = t.strip()
    for pre in FIELD_PREFIXES:
        if t.startswith(pre):
            return t[len(pre):].strip(" :：")
    return t


def looks_like_name(t):
    t = strip_field_prefix(t)
    if not (2 <= len(t) <= 16):
        return False
    if any(c.isdigit() for c in t) or ">" in t:
        return False
    if "*" in t:                          # 收款方全称「**发(个人)」是打码名，不是商户
        return False
    if any(lb in t for lb in PAGE_LABELS):
        return False
    if any(w in t for w in ANCHOR_WORDS) or any(w in t for w in REJECT_WORDS):
        return False
    if any(t.endswith(sf) for sf in NAME_SUFFIX_BLOCK):
        return False
    if has_cjk(t):
        return True
    return all(c.isalpha() or c in " -&'" for c in t)   # Netflix / UNIQLO 这类纯英文店名


def rank(lines, extract_amount):
    raw = []
    for i, line in enumerate(lines):
        text, h = line[0], line[1]
        got = extract_amount(text)[0]
        if not got or got <= 0:
            continue
        if any(w in text for w in UNPAID_WORDS):
            continue
        if any(w in text for w in REJECT_WORDS):
            continue
        # 左列标题、右列数值被拆成两行时，纯数字行自己不带语义，回头看左边那行：
        # 标题是屏蔽词就一起丢掉，标题是锚点就一起继承。
        context = text
        if not has_cjk(text) and i > 0:
            label = lines[i - 1][0]
            if any(w in label for w in REJECT_WORDS) or any(w in label for w in UNPAID_WORDS):
                continue
            context = f"{label} {text}"
        raw.append({"amount": got, "height": h, "line": text, "index": i, "ctx": context})

    out, seen = [], set()
    for c in raw:
        k = money(c["amount"])
        if k in seen:
            continue
        seen.add(k)
        out.append(c)

    tallest = max((c["height"] for c in out), default=0)
    for c in out:
        rel = c["height"] / tallest if tallest else 0
        anchored = any(w in c["ctx"] for w in ANCHOR_WORDS)
        c["score"] = rel + (ANCHOR_WEIGHT if anchored else 0)
        c["anchor"] = anchored
    out.sort(key=lambda c: -c["score"])
    return out


def merchant_name(lines, index):
    """整页里挑「最像商户名」的一行：字号最大者优先，同样大时取金额上方的那行。
    支付页的商户名就是页面上第二大的字，比挨着金额的那行可靠 ——
    挨着金额的常常是「实付」「神券优惠」这种字段名。"""
    best = None
    for i, line in enumerate(lines):
        name = strip_field_prefix(line[0])
        if not looks_like_name(name):
            continue
        key = (round(line[1], 4), 1 if i < index else 0)
        if best is None or key > best[0]:
            best = (key, name)
    return best[1] if best else None


def summary_page(lines):
    joined = " ".join(l[0] for l in lines)
    return any(re.search(p, joined) for p in SUMMARY_PATTERNS)


def ambiguous(cands):
    """前两名一样大、且都没锚点 —— 这页没有"唯一主角数字"，不该自动定。"""
    if len(cands) < 2:
        return False
    a, b = cands[0], cands[1]
    return (not a["anchor"]) and a["height"] <= b["height"] * AMBIG_RATIO


def parse_abs_date(lines, today=date(2026, 10, 20)):
    m = ABS_DATE.search(" ".join(l[0] for l in lines))
    if not m:
        return None
    d = date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    if d > today + timedelta(days=1):
        return None
    return (d, int(m.group(4)) if m.group(4) else None, int(m.group(5)) if m.group(5) else None)


def scan(lines, parsed_amount, parsed_note, extract_amount, today=date(2026, 10, 20)):
    """对位 ReceiptOCR.scan：返回 (金额, 依据, 备注, 商户, 日期, 候选, 需人工确认)"""
    lines = drop_status(lines)
    cands = rank(lines, extract_amount)
    amount, why = parsed_amount, "沿用解析器"
    hero = None
    if cands:
        by_h = sorted(cands, key=lambda c: -c["height"])
        # 有"主角数字"（明显比第二名大一号）就用它；没有才退回锚点+字高的打分。
        # 支付成功页一定有个大字金额；明细列表页全是同字号，只能靠锚点。
        if len(by_h) == 1 or by_h[0]["height"] >= HERO_RATIO * by_h[1]["height"]:
            hero = by_h[0]
    best = hero or (cands[0] if cands else None)
    if best and best["amount"] != parsed_amount:
        if hero or best["anchor"]:
            amount, why = best["amount"], ("最大字" if hero else "锚点行")
    merchant = merchant_name(lines, best["index"]) if best else None
    note = merchant if (merchant and len(parsed_note) > 20) else parsed_note
    need_confirm = summary_page(lines) or ambiguous(cands)
    if need_confirm and not (cands and cands[0]["anchor"]):
        amount = None
        why = "需确认"
    return amount, why, note, merchant, parse_abs_date(lines, today), cands, need_confirm
