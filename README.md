# 自动记账 · AutoLedger

一个**原生 iOS 记账 App**：用一句话记账，支付完截个图就自动入账。数据全在本机，不联网、不上传。

> Windows 上也能开发 iOS App —— 本工程通过 GitHub Actions 的 macOS runner 编译出**未签名 IPA**，你在 Windows 上用签名工具装到 iPhone 即可。

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [功能清单](#功能清单)
- [快速开始（三步装到手机）](#快速开始三步装到手机)
- [自动化记账怎么配](#自动化记账怎么配)
- [重签与数据恢复（重要）](#重签与数据恢复重要)
- [项目结构](#项目结构)
- [技术选型说明](#技术选型说明)
- [常见问题](#常见问题)

---

## 它解决什么问题

传统记账 App 的问题是：**每次记账要填表单**。打开 App → 点加号 → 输金额 → 选分类 → 选日期 → 保存。六步，坚持不了三天。

这个 App 把记账压到**一句话**，或者**一张截图**：

| 你说 | App 理解成 |
|---|---|
| 早餐豆浆油条 12 块 | 餐饮 · 支出 · 12 元 · 今天 |
| 打车 25 | 交通 · 支出 · 25 元 · 今天 |
| 昨天超市买了 86.5 | 购物 · 支出 · 86.5 元 · 昨天 |
| 星巴克咖啡三十二 | 餐饮 · 支出 · 32 元 · 今天（**中文数字也能听懂**）|
| 3 天前加油 400 | 交通 · 支出 · 400 元 · 3 天前 |
| 工资到账 8000 | 工资 · 收入 · 8000 元 · 今天 |

金额、分类、日期全部自动识别，你不用选任何东西。

---

## 功能清单

**自动记账**
- **截图入账**：支付结果页截一张图，App 用系统 Vision 在本机取字，自动解析金额 / 日期 / 商户，你只确认一次
- 自然语言解析：一句话拆出金额 / 分类 / 日期 / 备注
- 中文数字支持：`三十二` `一百二` `两千五` `十二点五`
- 内置 150+ 中文商户关键词库，命中即自动归类
- **分类自学习**：你手动改过一次分类，同样的商家下次自动归对
- 快捷指令 App Intents（装完即出现在快捷指令里，无需配置）
- URL Scheme，可被任何 App / 快捷指令调用
- **自动入账去重**：同账本同金额 60 秒内只记一笔，快捷指令和截图不会把同一笔消费记两次
- 周期账目：房租、水电、订阅，设一次每月自动生成

**记账本身**
- 首页一句话快速记账，实时预览识别结果
- 流水列表：按日分组、搜索、收支筛选、左滑删除
- 统计：分类饼图 + 分类排行 + 每日支出柱状图 + 近 6 月趋势
- 预算：月度总预算 + 分类预算，超支高亮、日均可用额度
- 多账本：日常 / 家庭 / 出差分开记，左滑切换
- 深色模式自动适配

**数据**
- 全本地存储（JSON），不联网
- 导出 CSV（带 BOM，Excel 直接打开不乱码）
- 完整备份 / 从备份恢复
- 每日自动备份到「文件」App 可见目录

---

## 快速开始（三步装到手机）

### 前提

| 需要 | 说明 |
|---|---|
| GitHub 账号 | 提供免费的 macOS 构建机 |
| iPhone + 数据线 | |
| 签名工具 | 你已有（Sideloadly / 爱思 / 其他都行） |
| Apple ID | 免费账号即可 |

### 第 1 步：推到 GitHub

```powershell
cd AutoLedger
git init -b main
git add .
git commit -m "AutoLedger: 自动记账"
```

去 GitHub 新建仓库（**不要**勾选 README / gitignore），然后：

```powershell
git remote add origin https://github.com/<你的用户名>/AutoLedger.git
git push -u origin main
```

> **Public 还是 Private？**
> Public：Actions 的 macOS 构建**不计额度**，随便构建。
> Private：每月 2000 分钟，macOS 按 10 倍扣，约 **5–8 次构建/月**。
> 个人项目建议先 Public。

> **两条关于触发的实测规则**（都能让你白等一趟）：
> 1. `push` 带 `paths` 过滤——只有改动 `AutoLedger/**`、`skeleton/**`、`project.yml` 或 workflow 本身才构建。改 README / BUILD_LOG 不触发，**空提交也不触发**（没有文件变更就匹配不上 paths）。
> 2. **是否跳过只看 push 的最后一个提交**：tip 提交的消息里有 `[skip ci]`，整次 push 就一个 workflow 都不跑，哪怕前面那个提交没带这个标记。攒一批再推时，把不带标记的提交放最后。

### 第 2 步：构建

推到 `main` 会直接跑 **`stage=app`**（`env.STAGE` 的兜底值是 `app`），几分钟出包 —— 实测 run#13 从排队到绿 **1m47s**，冷启动的第一轮可能要十几分钟。

手动 **Run workflow**（`workflow_dispatch`）时注意：**那个 `stage` 下拉框默认是 `skeleton`**，不改就只构建骨架，你会等到一个「成功」但产物不是正式包。

> **骨架（`stage=skeleton`）留作工具链体检。**
> 工程里有两个 target：`skeleton/`（1 个 Swift 文件、零原生依赖）和主工程（十几个文件 + Charts + AppIntents + Assets）。
> 骨架只验证「xcodegen → xcodebuild → Payload → ipa」这条链路本身通不通。
>
> - **骨架挂了** → 环境问题，别去翻 Swift 代码
> - **骨架绿了、`app` 挂** → 业务代码问题，报错一定带 `file:line`，别去改 workflow
>
> 什么时候值得重跑骨架：换了 runner 标签、升级了 Xcode、或者怀疑镜像本身出问题。平时不用。

跑完在运行页面底部 **Artifacts** 下载：
- `AutoLedger-ipa` → 解压得到 `AutoLedger.ipa`（用这个签名）
- `AutoLedger-app` → 有些签名工具要 `.app` 而不是 `.ipa`，备用

> **构建失败了？** 看 [BUILD_LOG.md](BUILD_LOG.md)。里面有**三类错误分诊表**（环境 / 依赖 / 代码）、已知风险点清单和记录模板。
> 核心原则：**每轮只改 1–2 处**，改完立刻构建，同一坑别踩第二次。

### 第 3 步：签名安装

用你现有的签名工具，把 `AutoLedger.ipa` 签上你的证书装到手机。

首次打开前，如果提示「未受信任的开发者」：
**设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任**

装好后打开 App，**第一件事是跑一遍「设置 → 数据 → 备份全部数据」再「从备份恢复」**——重签会清空本地数据，这条闭环必须在攒数据之前验过。然后再按下一节配自动化。

---

## 有 Mac？本地一键构建

不想用 GitHub Actions 时，在 Mac 上跑同一条流水线（逻辑与 CI 完全一致）：

```bash
cd AutoLedger
chmod +x tools/build_local.sh
./tools/build_local.sh              # Release
./tools/build_local.sh Debug        # Debug
./tools/build_local.sh --clean      # 先清空再构建
```

产出：
- `AutoLedger.ipa` —— 未签名，用签名工具自签
- `artifact-app/AutoLedger.app` —— 未签名，部分签名工具要 `.app` 而非 `.ipa`

依赖：完整 Xcode（只有 Command Line Tools 不够）、`xcodegen`、`python3`。
脚本会自己选 Xcode（默认版本优先）、失败时自动换版本重试，并打印错误摘要。

---

## 自动化记账怎么配

App 装好后，「快捷指令」里**已经自动出现两个动作**，不需要手动添加。注意系统注册的是**动作名**，不是 App 名——要搜 **「记一笔」** 和 **「本月收支」**，按「自动记账」找是找不到的；刚装完那几分钟还可能索引不到，等一下再搜。

### 方式一：截图入账（最省事，不用配任何东西）

付完款随手截一张图，然后打开 App → 首页右上角**取景框图标** → 选那张截图。App 在你手机上用系统 Vision 认字，解析出金额、日期、商户，你确认一下分类就入账。

- 全程本机识别，不联网、不上传，也**不申请相册权限**（只读你选中的那一张）
- 优先认「实付款 / 合计 / 扣款」这类账单锚点，所以「优惠 ¥5.00 实付 ¥31.00」取的是 31 不是 5
- 日期、时间、19 位订单号里的数字不会被当成金额
- 60 秒内同金额不会被重复记第二笔

想让它全自动：**快捷指令 → 自动化 → 新建自动化 → 触发条件选「截屏」**，加两个动作 —— `提取图像中的文本` → `记一笔`（把 `记一笔` 的 text 参数设成上一步的「文本」变量），并关掉「运行前通知」。

### 方式二：直接对 Siri 说

长按侧边按钮唤醒 Siri：

> 「用自动记账记一笔」

Siri 会追问内容，你说「早餐 12 块」，它自动识别并入账。**全程不用打开 App。**

### 方式三：URL Scheme（最灵活）

任何能打开链接的地方都能调用：

```
autoledger://add?text=早餐12元
autoledger://add?amount=25&kind=expense&category=交通&note=打车
autoledger://add?amount=8000&kind=income&category=工资&note=月薪
autoledger://summary
```

参数说明：

| 参数 | 说明 |
|---|---|
| `text` | 自然语言，交给解析引擎（推荐） |
| `amount` | 金额 |
| `kind` | `expense` / `income` |
| `category` | 分类名，如 `餐饮` `交通` |
| `note` | 备注 |
| `book` | 账本名，不填用当前账本 |

App 内「设置 → 自动化记账指南」有每条链接的**一键复制**。

### 方式四：挂到系统时机上

在「快捷指令」App 里建自动化，可选的时机（iOS 27）：

| 触发时机 | 用法 |
|---|---|
| **截屏时** | 主力方案：配 `提取图像中的文本` → `记一笔`，付款截图即入账 |
| 轻点背面 | 设置 → 辅助功能 → 轻点背面 → 指定快捷指令，付完反手敲两下 |
| 收到通知时 | **仅限确实会弹通知的场景**，比如银行 App 的扣款提醒。支付成功页的反馈发生在 App 界面内，不是通知中心，别指望通知链路抓每一笔 |
| 打开某个 App 时 | 如打开外卖 App 后弹一下记账 |
| 每天固定时间 | 每晚 22:00 提醒补记当天支出 |
| 主屏幕小组件 | 快捷指令放桌面，一点即记 |

> **上限在哪？** iOS 不允许 App 读取其他 App 的支付数据。所以「自动」能做到的是：**系统帮你抓一张截图或一段屏幕文字，识别和入账由 App 完成**——省掉的是「打开 App → 填六步表单」，不是「支付」这一步本身。谁跟你说能全自动静默抓全部支付流水，那是骗你。

---

## 重签与数据恢复（重要）

免费 Apple ID 签名的证书**只有 7 天有效期**，到期 App 打不开，必须重签。而**重签 = 重新安装 = 本地数据被清空**。

所以务必：

1. **每周固定一天重签**（比如周日晚），拿同一个 `AutoLedger.ipa` 重签即可，不用重新构建，约 2 分钟
2. **重签前先备份**：设置 → 数据 → 备份全部数据（JSON），存到「文件」或发给自己
3. **重签后恢复**：设置 → 数据 → 从备份恢复，选那个 JSON 文件

App 也会**每天自动备份**一份到「文件」App 的 `自动记账/AutoLedger备份/` 目录（保留最近 7 份），路径：`文件 App → 我的 iPhone → 自动记账`。

> 什么时候该买 ¥688/年 开发者账号：连续用满一个月、或者开始依赖它记所有账的时候。买了之后证书一年有效，不用再重签，也能用 iCloud 同步。

---

## 项目结构

```
AutoLedger/
├── project.yml                      # 主工程定义（XcodeGen，不提交 .xcodeproj）
├── BUILD_LOG.md                     # 构建失败分诊表 + 修复记录（每轮必填）
├── .gitignore                       # 忽略 build/、*.ipa、*.xcarchive、*.xcodeproj
├── .github/workflows/build-ipa.yml  # 云端 macOS 构建（skeleton / app 两阶段）
├── skeleton/                        # 零原生代码骨架，只用来验证工具链
│   ├── project.yml                  # 独立工程，1 个 target、无资源目录
│   └── Skeleton/SkeletonApp.swift   # 唯一源文件，只显示「构建链路 OK」
├── tools/
│   ├── build_local.sh               # 有 Mac 时本地一键构建（逻辑与 CI 一致）
│   ├── ensure_scheme.py             # 补共享 scheme（project.yml 未声明 scheme: 时必需）
│   └── make_icon.py                 # 图标生成脚本（Pillow，可重复运行）
└── AutoLedger/
    ├── AutoLedgerApp.swift          # 入口
    ├── Info.plist                   # URL Scheme / 文件共享配置
    ├── Models/
    │   ├── Models.swift             # 数据模型 + 聚合类型 + 格式化
    │   └── ChineseNumber.swift      # 中文数字解析（三十二 / 一百二 / 两千五）
    ├── Store/
    │   ├── LedgerStore.swift        # 主数据仓库：持久化 / 统计 / 预算 / 周期账目 / 备份恢复
    │   └── MerchantRuleEngine.swift # 商户关键词规则库 + 自学习
    ├── Parser/
    │   ├── NaturalParser.swift      # 自然语言解析：金额 / 日期 / 收支方向 / 备注
    │   └── ReceiptOCR.swift         # Vision 本机取字（按阅读顺序输出，喂给 NaturalParser）
    ├── Intents/
    │   └── AutoLedgerIntents.swift  # App Intents + AppShortcuts + URL Scheme 路由
    ├── Design/
    │   └── Theme.swift              # 配色 / 卡片 / 分类徽章 / 空状态
    ├── Views/
    │   ├── HomeView.swift           # 首页（含 RootView / TabView）+ 截图入账入口
    │   ├── TransactionListView.swift
    │   ├── AddTransactionView.swift # 添加/编辑 + 详情页
    │   ├── ReceiptScanSheet.swift   # 截图入账：选图 → 识别 → 确认
    │   ├── StatsView.swift          # 饼图 / 排行 / 趋势（Swift Charts）
    │   ├── BudgetView.swift
    │   ├── SettingsView.swift       # 导出/恢复/周期账目/账本
    │   └── ShortcutGuideView.swift  # 自动化配置指南
    └── Assets.xcassets/             # App 图标 + 主题色
```

### 为什么要拆一个 skeleton 工程

Windows 上不能本地跑 `xcodebuild`，只能靠云端。如果第一次就把 3000 行原生代码推上去、挂了 20 个错，**根本分不清是工具链问题还是代码问题** —— 每个错都要重新怀疑一遍整个方案，这是最消耗信心的。

`skeleton/` 是刻意做的最小工程：1 个 Swift 文件、不引用 Charts / AppIntents、连 Assets 目录都不带（避免 `ASSETCATALOG_COMPILER_APPICON_NAME` 找不到图标而报错，污染判断）。

两个工程**共用同一套 workflow 步骤**，只靠 `stage` 输入切换路径。所以骨架绿了就证明工具链没问题，之后主工程的每个报错都必然是代码问题。

---

## 技术选型说明

| 选择 | 理由 |
|---|---|
| **原生 SwiftUI** | 你要的是 iOS 端。原生才能用 App Intents / AppShortcuts（快捷指令深度集成），RN/Flutter 这块能力受限 |
| **XcodeGen** | 工程文件由 `project.yml` 生成，避免 `.xcodeproj` 冲突，也方便 CI 生成 |
| **JSON 文件存储** | 数据量小（几千笔）、无需迁移、备份就是拷文件，比 CoreData 简单可靠 |
| **Swift Charts** | 系统框架，无第三方依赖，暗色模式自动适配 |
| **App Intents** | iOS 17 的快捷指令标准接口，装完即出现在快捷指令里，用户体验最好 |

**为什么不用 Expo / RN？** 记账 App 的核心是 App Intents 和本地数据，原生实现更直接，且构建链路（XcodeGen → xcodebuild）比 Expo prebuild + CocoaPods 更少环节、更少坑。

---

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| Actions 构建失败 | 先看是哪个 stage 挂的。**骨架挂 = 环境问题；主工程挂 = 代码问题**。再看「错误摘要」段落（只打最后 80 行 error），按 [BUILD_LOG.md](BUILD_LOG.md) 的三类分诊表处理 |
| 骨架构建就失败了 | 说明是工具链问题，别去改 Swift。检查 workflow 的 Xcode 选择步骤、`xcodegen --version`、`xcrun --sdk iphoneos --show-sdk-version` 输出 |
| 骨架绿了但 `app` 阶段挂 | 这是代码问题，报错一定带 `file:line`，按位置逐个修。**每轮只改 1–2 处**，改完立刻重跑 |
| 找不到 scheme | `project.yml` 里没有 `scheme:` 块时 XcodeGen 不生成 `.xcscheme`，`archive -scheme` 就会失败。现在 `project.yml` 显式声明了 scheme，CI 里只剩一步存在性校验；本地脚本 `tools/build_local.sh` 仍会调 `tools/ensure_scheme.py` 兜底 |
| 构建失败但换 Xcode 后成功 | 镜像里多个 Xcode 只有默认版本预装 iOS 平台组件，workflow 会自动换版本重试 |
| 装不上 / Unable to install | 手机没信任电脑、锁屏了、或 USB 线只供电 |
| App 装上打不开 | 先「信任开发者」；仍不行就重签一次 |
| 重签后数据没了 | 正常现象。用「从备份恢复」导入之前备份的 JSON |
| 识别不出金额 | 「早餐 12」这种不带单位的也能认（全文没有阿拉伯数字时会走中文数字兜底档）。真取不到就换成「早餐 12 元」 |
| 快捷指令里搜不到记账动作 | 系统注册的是**动作名**「记一笔」「本月收支」，不是 App 名「自动记账」；另外刚装完有索引延迟，等一下再搜。仍找不到就看 IPA 里 `Metadata.appintents/` 齐不齐（见 BUILD_LOG 第 8 轮） |
| 截图入账取错金额 | 账单**汇总页**（「本月已消费 ¥12,345.00」）会被当成一笔消费。只截**支付成功页**；识别结果入账前可以改分类，不满意就换一张 |
| 同一笔被记了两次 | 不会：机器来源（快捷指令 / URL / 截图）60 秒内同账本、同收支方向、同金额只记一次。真需要两笔同金额，走首页手动记 |
| 分类不准 | 在详情页点「让 XX 以后自动归到 YY」，之后就会记住 |

> **预期心理准备**：第一次构建主工程失败 1–2 轮是正常的，不用怀疑方案。平均 3–4 轮能压到 1–2 轮，靠的就是「每轮只动一处 + 有记录」。

---

## 免责

- 数据仅存本机，卸载 App 即丢失（除非有备份）
- 未签名 IPA 需自行签名，签名有效期取决于你的证书
- 本工程不含任何统计、上报、联网代码
