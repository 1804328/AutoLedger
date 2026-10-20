"""把 NaturalParser.extractAmount 的分档逻辑忠实移植成 Python，验证正则语义与顺序。
不验证 Swift 语法，只验证：屏蔽表是否等长、锚点档是否抢在余额前、无单位中文数字档的守卫。
"""
import re

UNIT_PATTERNS = [
    r"(?:[¥￥]|RMB|rmb|人民币)\s*(\d{1,3}(?:,\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)",
    r"(\d{1,3}(?:,\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*(?:元整|块钱|元|块|圆)",
    r"(\d+(?:\.\d+)?)\s*(?:毛|角)",
]
ANCHOR = r"(?:实付款|实付|已付款|已付|付款金额|支付金额|扣款金额|扣款|扣费|合计|总计|金额|支出|消费|支付)[:：]?\s*[-－]?[¥￥]?\s*([\d,]+(?:\.\d{1,2})?)"
CHINESE = r"([零〇一二两三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟]+)\s*(?:元整|块钱|元|块|圆)"
PLAIN = r"(?<![\d.,])(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)(?![\d.])"
CHINESE_BARE = r"([零〇一二两三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟点點]+)"
NOISE = [
    r"\d{4}[-/年]\d{1,2}[-/月]\d{1,2}\s*[日号]?",
    r"\d{1,2}\s*月\s*\d{1,2}\s*[日号]",
    r"\d{1,2}:\d{2}(?::\d{2})?",
    r"\d+\s*天前",
    r"(?:周|星期|礼拜)[一二三四五六日天]",
    r"\d{1,2}\s*[日号]",
    r"(?<![\d月.])\d{1,2}\s*月",
    r"\d{4,}年",
    r"\d{8,}",
    r"\d+\*+\d+",                                      # 6214****8888 这种打码卡号
]
NOTE_NOISE = ["支付成功", "付款成功", "交易成功", "扣款成功", "已支付", "已付款", "未付款",
              "实付金额", "实付", "付款金额", "支付金额", "订单号", "交易单号", "支付方式",
              "支付宝", "账户余额", "余额", "零钱", "花呗", "余额宝",
              "元整", "块钱", "元", "块", "圆", "花了", "花费", "支付", "付了", "消费",
              "买了", "一共", "总共", "合计", "共计", "价格", "金额", "用了"]
NOTE_MONEY_RESIDUALS = [r"\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?", r"\d+\.\d{1,2}"]
DATE_STRIP = [r"\d+\s*天前", r"(上|这|本)?(?:周|星期|礼拜)[一二三四五六日天]",
              r"\d{1,2}\s*月\s*\d{1,2}\s*[日号]", r"(?<![\d月])\d{1,2}\s*[日号](?![\d])",
              r"\d{1,2}:\d{2}"]
RELATIVE = ["大前天", "前天", "昨天", "今天", "今日", "刚才", "刚刚", "现在", "明天"]

DIGIT = {"零": 0, "〇": 0, "洞": 0, "一": 1, "壹": 1, "幺": 1, "二": 2, "贰": 2, "两": 2, "俩": 2,
         "三": 3, "叁": 3, "四": 4, "肆": 4, "五": 5, "伍": 5, "六": 6, "陆": 6, "七": 7, "柒": 7,
         "八": 8, "捌": 8, "九": 9, "玖": 9}
UNIT = {"十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1000, "仟": 1000}
BIG = {"万": 10_000, "萬": 10_000, "亿": 100_000_000, "億": 100_000_000}


def cn_parse(text):
    """ChineseNumber.parse 的移植"""
    total = section = pending = last_unit = 0.0
    saw_zero = saw_any = False
    dec = None
    in_dec = False
    scale = 0.1
    for ch in text:
        if ch in ("点", "點"):
            if dec is None:
                in_dec = True
                dec = 0.0
            continue
        if ch in DIGIT:
            d = DIGIT[ch]
            if in_dec:
                dec += d * scale
                scale /= 10
                continue
            if d == 0:
                saw_zero = True
                pending = 0
            else:
                pending = pending * 10 + d
            saw_any = True
            continue
        if ch in UNIT:
            if pending == 0:
                pending = 1
            section += pending * UNIT[ch]
            pending = 0
            last_unit = UNIT[ch]
            saw_any = True
            continue
        if ch in BIG:
            section += pending
            if section == 0:
                section = 1
            total += section * BIG[ch]
            section = pending = 0
            last_unit = BIG[ch]
            saw_any = True
            continue
        return None
    if not saw_any:
        return None
    if 0 < pending < 10 and not saw_zero and last_unit >= 100:
        pending *= last_unit / 10
    r = total + section + pending
    if dec is not None:
        r += dec
    return r


def mask(text):
    """等长空格屏蔽，同时返回是否真的等长（Swift 侧依赖这个不变量）"""
    s = text
    for p in NOISE:
        for m in sorted(re.finditer(p, s), key=lambda x: x.start(), reverse=True):
            s = s[:m.start()] + " " * (m.end() - m.start()) + s[m.end():]
    assert len(s) == len(text), "屏蔽改变了长度，span 偏移会错位"
    return s


def num(pat, s):
    m = re.search(pat, s)
    return m


def extract_amount(text):
    masked = mask(text)
    m = re.search(ANCHOR, masked)
    if m:
        v = m.group(1).replace(",", "")
        try:
            d = float(v)
        except ValueError:
            d = None
        if d is not None and d > 0:
            return d, "0-账单锚点", masked, m.span()
    for p in UNIT_PATTERNS:
        m = re.search(p, masked)
        if m:
            v = m.group(1).replace(",", "")
            try:
                d = float(v)
            except ValueError:
                continue
            if m.group(0).find("毛") >= 0 or m.group(0).find("角") >= 0:
                d /= 10
            return d, "1-带单位", masked, m.span()
    m = re.search(CHINESE, masked)
    if m:
        d = cn_parse(m.group(1))
        if d is not None:
            return d, "2-中文+单位", masked, m.span()
    m = re.search(PLAIN, masked)
    if m:
        try:
            return float(m.group(1).replace(",", "")), "3-纯数字", masked, m.span()
        except ValueError:
            pass
    if not re.search(r"\d", masked):
        m = re.search(CHINESE_BARE, masked)
        if m:
            cn = m.group(1)
            if len(cn) >= 2 or any(c in "十百千万亿拾佰仟" for c in cn):
                d = cn_parse(cn)
                if d is not None:
                    return d, "4-裸中文数字", masked, m.span()
    return None, "无", masked, None


def extract_note(text, span):
    s = text
    if span:
        s = s[:span[0]] + " " + s[span[1]:]
    for w in RELATIVE:
        s = s.replace(w, " ")
    s = mask(s)                                    # 与 Swift 侧对齐：先屏蔽再剥日期
    for p in DATE_STRIP:
        s = re.sub(p, " ", s)
    for p in NOTE_MONEY_RESIDUALS:
        s = re.sub(p, " ", s)
    for t in ["¥", "￥", "RMB", "rmb", "人民币"]:
        s = s.replace(t, " ")
    for n in NOTE_NOISE:
        s = s.replace(n, " ")
    s = re.sub(r"[，,。.；;：:、!！?？~～|/\\\-_+=*#@()（）\[\]【】\"'“”‘’]", " ", s)
    while "  " in s:
        s = s.replace("  ", " ")
    return s.strip()


CASES = [
    # (输入, 期望金额, 说明) —— 前三条是 README 自己宣称过的例子
    ("早餐豆浆油条 12 块", 12.0, "README 例 1"),
    ("打车 25", 25.0, "README 例 2"),
    ("昨天超市买了 86.5", 86.5, "README 例 3"),
    ("星巴克咖啡三十二", 32.0, "README 例 4：裸中文数字（旧版必失败）"),
    ("3 天前加油 400", 400.0, "README 例 5：旧版会记成 3 元"),
    ("工资到账 8000", 8000.0, "README 例 6"),
    ("一百二", 120.0, "口语省略"),
    ("两千五", 2500.0, "口语省略"),
    ("十二点五", 12.5, "中文小数"),
    ("10月20日 打车 25", 25.0, "OCR 场景：日期在前"),
    ("2026年10月20日 14:32  消费 ¥36.00", 36.0, "OCR 场景：完整时间戳"),
    ("支付成功\n¥36.00\n星巴克咖啡\n支付方式 零钱\n2026年10月20日 14:32", 36.0, "微信支付成功页"),
    ("支付宝到账 实付¥36.00 余额¥1,286.50", 36.0, "余额干扰：必须取实付不是余额"),
    ("本单已付款25.00元，账户余额1,286.50元", 25.0, "无货币符号的余额干扰"),
    ("交易单号 2026102014320012345 金额 18.00", 18.0, "19 位订单号必须被屏蔽"),
    ("尾号1234 储蓄卡 支付 45.00元", 45.0, "卡号后四位 + 带单位档"),
    ("上周三 请客吃饭 320", 320.0, "裸中文数字档不能把「三」读成 3 元"),
    ("上午十一点开会 打车 18", 18.0, "有阿拉伯数字时不启用裸中文档"),
    ("一共花了3块5", 3.0, "已知局限：「3块5」要说成「3块5毛」才读到 3.5，旧版同此行为"),
]

# 第二批：对抗性用例，专挑"取第一个命中"会翻车的排序
CASES2 = [
    ("支付成功 优惠¥5.00 实付¥31.00", 31.0, "锚点档必须跳过优惠价（旧版会取 5.00）"),
    ("¥36.00 交易成功 建行储蓄卡(1234)", 36.0, "首档带符号，括号里卡尾号不误取"),
    ("星期三 午饭 三十五", 35.0, "星期屏蔽后裸中文数字档"),
    ("周一开会打车二十", 20.0, "「周一」不能被读成 1 元"),
    ("这个月工资 8000", 8000.0, "「这个月」无数字，不该影响"),
    ("2026年 房租 5000", 5000.0, "年份屏蔽"),
    ("3楼食堂 15元", 15.0, "「3楼」在前但带单位档优先命中 15"),
    ("退款¥25.00", 25.0, "退款金额本身"),
    ("2026/10/20 14:32:08 消费 68.88", 68.88, "完整时间戳 + 两位小数"),
    ("本月已消费¥12,345.00 余额¥8,000.00", 12345.0, "已知局限：账单汇总页会被当成一笔消费，"
                                                     "需要快捷指令侧只放过「支付成功」页"),
    ("奶茶 12", 12.0, "纯数字兜底不能被空格/无单位打败"),
    ("打车从3号门到公司 25元", 25.0, "「3号」屏蔽，带单位档取 25"),
]

print(f"{'输入':<34} {'档位':<14} {'金额':>10}  {'期望':>8}  备注")
print("-" * 118)
fails = 0
results = []
for text, want, label in CASES + CASES2:
    got, tier, masked, span = extract_amount(text)
    results.append((text, got, tier, masked, span))
    note = extract_note(text.replace("\n", " "), span) if span else ""
    ok = (got == want)
    if not ok:
        fails += 1
    show = text.replace("\n", "\\n")
    print(f"{show[:32]:<34} {tier:<14} {str(got):>10}  {str(want):>8}  "
          f"{'OK ' if ok else 'FAIL'} {label}｜备注={note[:26]!r}")
print("-" * 118)
total = len(CASES) + len(CASES2)
print(f"{total - fails}/{total} 通过，失败 {fails} 条")
from collections import Counter
print("档位分布（看锚点档到底抢了多少次）:",
      dict(Counter(t for (_, _, t, _, _) in results)))
