"""真机截图版式跑当前选择逻辑：支付宝「账单详情」伊清烧烤 -18.00。

行集来自 real_geometry.py 对 IMG_1996.JPG 的水平投影实测（像素行高 / 2622），
文字内容按 real_bands.png 逐行核对。split 形态（标题和值各一个 observation）
就是 Vision 对这种左右版式的实际输出粒度。

被测的是 receipt_logic 那份移植实现 —— tools/parity_check.py 保证它和 Swift 一致。
「改动前记成 4 元」这个事实的证据是真机截图 IMG_1997（App 详情页显示 -¥4、
备注是一长串倒序整页噪声），不在这里复现：那是改动前的另一套代码，
在这儿重写一遍只会得到一份没人验证过的平行实现。
"""
import os
import sys
from datetime import date

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parser_check import extract_amount
import receipt_logic as L

# (文本, 实测归一化字高)：支付宝「账单详情」伊清烧烤 -18.00
ALIPAY_DETAIL = [
    ("15:57", .017),
    ("账单详情", .021), ("全部账单", .021),
    ("伊清烧烤", .0156),
    ("-18.00", .0278),
    ("交易成功", .0156),
    ("支付时间", .0156), ("2026-10-18 22:04:59", .0114),
    ("付款方式", .0156), ("花呗", .0156),
    ("商品说明", .0145), ("收钱码收款", .0145),
    ("支付奖励", .0145), ("立即领取4积分", .0145),
    ("收款方全称", .0145), ("**发(个人)", .0145),
    ("账单管理", .0156), ("本月餐饮美食是最大支出类目，看看花在哪里了", .0156),
    ("账单分类", .0145), ("餐饮美食", .0145),
    ("标签", .0145), ("请选择", .0145),
    ("使用记账本，查看自定义分类、标签统计", .0145),
    ("计入收支", .0156), ("备注", .0145), ("添加", .0145),
    ("联系收款方", .0164), ("查看往来记录", .0164),
    ("AA收款", .0164), ("往来流水证明", .0164),
]

# 真机截图 2（App 详情页）里实际记下来的那串整页噪声备注
ALIPAY_BLOB = ("AA收款 往来流水证明 联系收款方 查看往来记录 备注 添加 计入收支 使用记账本 "
               "查看自定义分类 标签统计 标签 请选择 账单分类 餐饮美食 账单管理 本月餐饮美食是最大"
               "支出类目 看看花在哪里了 更多 发 个人 立即领取 积分 收钱码收款 反馈与投诉 伊清烧烤 全部账单")

# 解析器在整页噪声上先取到的数字 —— 真机上就是这个 4（备注里那串「立即领取 积分」就是它的出处）。
# 传进 scan 就是要看候选金额这一层能不能把它推翻。
PARSED_AMOUNT = 4.0

amount, why, note, merchant, d, cands, confirm = L.scan(
    ALIPAY_DETAIL, PARSED_AMOUNT, ALIPAY_BLOB, extract_amount)

print(f"解析器原始结论 {PARSED_AMOUNT:.2f} → 选择层结论 "
      f"{'' if amount is None else f'{amount:.2f}'}（依据：{why}）")
print(f"备注={note}  商户={merchant}  日期={d[0]} {d[1]}:{d[2]:02d}  "
      f"需确认={confirm}  候选={[L.money(c['amount']) for c in cands]}")
print("-" * 78)

checks = [
    ("大字金额把解析器误取的 4 元改判成 18.00", amount == 18.00),
    ("改判依据是「最大字」而不是碰巧沿用", why == "最大字"),
    ("整页噪声备注被换成商户名", note == "伊清烧烤"),
    ("日期取截图里的支付时间而不是今天", d[0] == date(2026, 10, 18)),
    ("精确到时分", (d[1], d[2]) == (22, 4)),
    ("详情页不该判成需人工确认", confirm is False),
    ("「4积分」没混进候选（被屏蔽词丢掉）", all(c["amount"] != 4.0 for c in cands)),
]
bad = [n for n, ok in checks if not ok]
for n, ok in checks:
    print(("OK   " if ok else "FAIL ") + n)
print("\n" + ("真机实测版式通过" if not bad else f"{len(bad)} 条不符：{bad}"))
sys.exit(1 if bad else 0)
