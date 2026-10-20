# OCR 选择逻辑的用例台架

Windows 上没有 swiftc，跑不了 Swift 测试；Vision 又只在真机上有。
所以这套台架把 `ReceiptOCR` / `NaturalParser` 的选择逻辑**忠实移植成 Python**，
用真实截图量出来的几何当用例，验证「选哪个数字」这件事。

它证明的是语义和顺序，不是 Swift 语法，也不是 Vision 的识别质量。
语法靠 `tools/check_swift.py`（括号配平 + BOM），
识别质量只能在真机上验。

| 脚本 | 干什么 |
|---|---|
| `parser_check.py` | `NaturalParser.extractAmount` 五档取金额的 31 条回归（import 时自动跑完并打印） |
| `receipt_logic.py` | `ReceiptOCR` 的候选排序 / hero 判定 / 商户名 / 汇总页判定的移植实现（被下面两个引用） |
| `corpus_check.py` | 21 种支付页版式 × merged/split 两种 Vision 分行习惯 = 42 条断言 |
| `receipt_check.py` | 真机那张支付宝账单详情（实测字高）跑当前逻辑，7 条断言 |
| `real_geometry.py` | 给一张截图，按水平投影量出每行文字的实际像素高度，`--montage` 出图供逐行核对 |
| `../parity_check.py` | 把 Swift 里的词表/正则逐条和这里的移植比对，防止「Python 绿了但仓库里是另一套」 |

改选择逻辑时的顺序：先在 `receipt_logic.py` / `parser_check.py` 里改到全绿，
再原样搬进 Swift，最后跑 `python tools/parity_check.py` 确认两边还是一回事。

```
PYTHONIOENCODING=utf-8 python tools/ocr_probe/corpus_check.py
PYTHONIOENCODING=utf-8 python tools/ocr_probe/receipt_check.py
PYTHONIOENCODING=utf-8 python tools/parity_check.py
PYTHONIOENCODING=utf-8 python tools/check_swift.py
```

`real_geometry.py` 的截图路径不入库（各人相册位置不同），要重新量就自己传：

```
python tools/ocr_probe/real_geometry.py /路径/IMG_1996.JPG /tmp/bands.png --montage
```
