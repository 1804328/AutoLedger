# BUILD_LOG

构建失败与修复记录。**同一个坑不踩第二次。**

---

## 铁律

1. **每轮只改 1–2 处**，改完立刻构建。一次改五处，成功了也不知道哪处起了作用，失败了也不知道是谁的锅。
2. **先分类再动手**（见下方分诊表）。同一个 `error:` 可能属于三类完全不同的原因，改错方向会白烧一轮。
3. **每轮记录到本文件**，包括「猜错了」的那轮 —— 排除法也是信息。
4. **报错先看摘要**：workflow 已经只打最后 80 行 `error:`，不要翻 500 行日志。

---

## 分诊表：三类错误，三种改法

| 类别 | 典型特征 | 改哪里 | 判断依据 |
|---|---|---|---|
| **A. 环境 / 工具链** | `xcodebuild: error: SDK "iphoneos" cannot be located`<br>`does not contain a scheme named`<br>`xcodegen: command not found`<br>`Unable to find a destination matching`<br>`No signing certificate` | **改 workflow** | 骨架构建（stage=skeleton）也会挂 → 一定是 A 类 |
| **B. 第三方库 / 依赖版本** | `Module 'X' not found`<br>`No such module`<br>`Undefined symbol`<br>`requires a higher minimum deployment target`<br>`CocoaPods could not find compatible versions` | **查版本**，不动业务代码 | 只在引入某个库之后才出现 |
| **C. 自己的代码** | 带 `file:line` 的编译错误<br>`cannot find 'x' in scope`<br>`value of type 'X' has no member 'y'`<br>`missing argument for parameter`<br>`type 'X' does not conform to protocol 'Y'` | **按 file:line 修 Swift** | 骨架绿了、主工程挂 → 一定是 C 类 |

> **核心判据：骨架构建的结果，决定了你该看 A 还是看 C。**
> 骨架挂 = 环境问题，别去翻 Swift 代码。
> 骨架绿、主工程挂 = 代码问题，别去改 workflow。

---

## 分阶段构建：为什么这么设计

Windows 上没法本地跑 `xcodebuild`，只能靠云端。如果第一次就把 3000 行原生代码推上去，挂了 20 个错，根本分不清是工具链问题还是代码问题 —— 每个错都要重新怀疑一遍整个方案。

所以拆成两个阶段，**共用同一套 workflow、同一套工具链步骤**：

```
阶段 1  stage=skeleton  →  skeleton/ 工程
        · 只有 1 个 Swift 文件
        · 不引用 Charts / AppIntents / 资源目录
        · 编不过 ⇒ 100% 是环境或 workflow 问题（A 类）

        ✅ 绿了再往下
        ▼
阶段 2  stage=app       →  完整业务工程
        · 15 个 Swift 文件 + Charts + AppIntents + Assets
        · 编不过 ⇒ 100% 是我们自己的 Swift 问题（C 类）
```

一旦变量被隔离，每轮报错就自动落到唯一类别里，不需要猜。

### 怎么跑

| 阶段 | 触发方式 | 耗时 |
|---|---|---|
| 骨架 | push 到 main（默认）/ 手动 Run workflow 选 `skeleton` | 约 8–10 分钟 |
| 主工程 | 手动 Run workflow 选 `app` | 约 10–15 分钟 |

> push 触发默认只跑骨架，是为了不烧额度。要出正式包请手动选 `app`。

---

## 记录模板

复制下面这段，每轮填一条：

```markdown
### 第 N 轮 · YYYY-MM-DD · stage=skeleton|app

**结果**：❌ 失败 / ✅ 通过

**错误摘要**（只贴 `error:` 那几行）：
```
<粘贴>
```

**分类**：A 环境 / B 依赖 / C 代码

**判断依据**：
<为什么归到这一类>

**本轮改动**（1–2 处）：
1. `path/to/file:行号` — <改了什么>

**结果**：<修好了 / 换了个错 / 同样错还在>

**结论**：<下次遇到同样报错，直接怎么处理>
```

---

## 已知风险点（首次构建前预判）

以下是静态审查时识别出的、**只有编译器能最终确认**的地方。构建失败时优先对照这张表：

| # | 位置 | 风险 | 类别 | 若报错的修法 |
|---|---|---|---|---|
| 1 | `Intents/AutoLedgerIntents.swift` | `AppIntent` / `AppShortcutsProvider` 的协议签名在 iOS 17 上较严格，`@Parameter` 与 `ParameterSummary` 组合容易报 conformance 错 | C | 按报错逐个补 `static var` 类型标注；必要时先注释掉 `AutoLedgerShortcuts` 确认其余能过 |
| 2 | `Intents/AutoLedgerIntents.swift` | `IntentDialog(stringLiteral:)` 需要 `String` 字面量，传变量可能报错 | C | 改用 `IntentDialog(stringLiteral: str)` 若已报错，则用 `.result(dialog: "...")` 直接内联字符串 |
| 3 | `Views/StatsView.swift` | `SectorMark` 需 iOS 17+（已满足），但 `Chart(collection)` 要求元素 `Identifiable` | C | `CategoryTotal` 已加 `id`，若仍报错则改 `Chart(breakdown, id: \.category.id)` |
| 4 | `Store/LedgerStore.swift` | `LedgerStore` 非 `@MainActor`，但被 SwiftUI `@StateObject` 与 Intent 的 `@MainActor` 方法同时访问 | C | 若报 actor 隔离错，给 `LedgerStore` 加 `@MainActor`，并把 `shared` 的初始化改成惰性 |
| 5 | `Views/HomeView.swift` | `RootView` 里 `.onChange(of: scenePhase)` 双参数闭包需 iOS 17 | C | 已满足；若报错检查 deployment target 是否真是 17.0 |
| 6 | `project.yml` | `scheme:` 声明格式若与 XcodeGen 版本不符，可能不生成 scheme | A | 已有 `ensure_scheme.py` 兜底；若仍失败，看 `xcodebuild -list` 输出 |
| 7 | `AutoLedger/Info.plist` | `UILaunchScreen` 空 dict + 缺少 `UILaunchStoryboardName` 在部分 Xcode 版本可能警告 | A | 警告可忽略；若报错补 `<key>UILaunchStoryboardName</key><string></string>` |

---

## 修复历史

### 第 0 轮 · 2026-10-19 · 静态审查（未构建）

**做了什么**：Windows 上无法 `xcodebuild`，做了静态审查 —— 括号平衡（15 个文件全部平衡）、顶层类型重复检查（仅 `Category` / `Theme` 的合法 type+extension）、YAML 与 plist 语法校验。

**主动修掉的已知问题**（构建前就消除的）：
1. 元组 KeyPath：`ForEach(tuples, id: \.field)` 在 Swift 不合法 → 改为 `CategoryTotal` / `DayGroup` / `DayPoint` / `MonthPoint` 等具名 struct
2. `Scene` 上挂 `.onChange`：`App` 的 `body` 返回 `Scene`，不是 `View` → 移到 `RootView` 的 `View` 上
3. `@MainActor` 的 `LedgerStore` 在 `App` 初始化时同步访问 → 去掉 `@MainActor`（Swift 5.9 默认并发检查较宽松）
4. `URLRouter.handle` 标了 `@MainActor` 但从 `onOpenURL` 调用 → 去掉标注
5. `Category.color` 在 `Codable` struct 里 → 改为 `extension` 里的计算属性
6. 数据丢失缺口：免费签名 7 天重签会清空沙盒 → 补「从备份恢复」+ 每日自动备份到 Documents

**结论**：静态审查能挡住语法级和结构级错误，**挡不住 SDK 语义 / API 可用性 / 协议 conformance** 这类只有编译器知道的问题。所以必须走分阶段构建。

---

### 第 1 轮 · 2026-10-19 · 独立审计（未构建）

**做法**：派一个独立 agent 做逐行审计，交叉核对 Apple 官方文档。这轮没有跑构建，但结论价值很高。

**结果**：❌ 发现 1 个**必然失败**的配置错误

**分类**：A 环境（构建配置）

**判断依据**：错误发生在编译任何 Swift 文件之前，与代码质量无关。

**本轮改动**（2 处，都属于配置）：
1. `project.yml` + `skeleton/project.yml` — `SWIFT_VERSION: "5.9"` → `"5.0"`
   - `SWIFT_VERSION` 是**语言模式**，只接受 `4.0 / 4.2 / 5.0 / 6.0`，不是编译器版本
   - 写成 `5.9` 会直接报 `error: SWIFT_VERSION '5.9' is unsupported`
   - 同时显式加 `SWIFT_STRICT_CONCURRENCY: minimal`
   - **不要**改成 `6.0`：会把下面的 `@MainActor` / `static var` 问题从警告升级为错误
2. `.github/workflows/build-ipa.yml` — `runs-on: macos-26` → `macos-14`
   - `macos-26` 在公开仓库长期拿不到 runner（一直 queued）
   - Xcode 选择逻辑改为通用版：默认 ≥15 直接用，否则挑 `sort -V` 最大
   - 构建失败重试循环去掉 `Xcode_26` 硬编码

**结论**：**`SWIFT_VERSION` 是这类工程最隐蔽的坑** —— 它看起来像编译器版本，实际是语言模式。以后任何 XcodeGen 工程都先检查这一行。

---

### 第 2 轮 · 2026-10-19 · 按审计建议加固

**本轮改动**（3 处，都是消除 Swift 6 迁移风险）：
1. `StatsView.swift` — `ForEach(Array(breakdown.enumerated()), id: \.element.id)` → `ForEach(breakdown)`
   - 去掉「元组 keypath → 成员访问 → 元组解构」三层组合
   - 注：Swift 5.9 其实**支持**元组元素 keypath，这条不是硬错误，属防御性修改
2. `AutoLedgerIntents.swift` ×3 — `static var openAppWhenRun: Bool = false` → `static var openAppWhenRun: Bool { false }`
   - 可变 static 属性在 Swift 6 是并发安全错误，且 iOS 18+ 已 deprecated
3. `AutoLedgerIntents.swift` ×3 — 删掉 `perform()` 上的 `@MainActor`
   - `AppIntent.perform()` 是非隔离要求，用 `@MainActor` 满足它在 Swift 6 是错误
   - 而且**不需要**：`LedgerStore` 是普通 class，非 actor 隔离

**踩坑记录（重要）**：
- 第一次用 PowerShell `Set-Content` 改 workflow → 加了 **UTF-8 BOM** 且破坏了 YAML 缩进 → run#1 失败
- 第二次用 PowerShell 正则批量改 `.swift` → 破坏括号平衡（27/30）并引入 CRLF → 从 git 恢复
- **教训：改 Swift / YAML 一律用 `edit` 工具做精确替换，不要用 PowerShell 批量正则替换。**
  PowerShell 的 `Set-Content` 默认带 BOM，`Get-Content -Raw` + 正则会破坏多字节字符与缩进。

---

### 第 3 轮 · 2026-10-19 · 排队问题排查

**现象**：run#2、run#3 长期 `status: queued`，`runner_id: null`

**排查过程**：
1. 先怀疑 `macos-26` 标签不可用 → 改 `macos-14`，仍 queued
2. 查同账号另一个仓库 `apple-` → 发现它的 run#12、#13 也 queued
3. 而 `apple-` 的 run#9/#10/#11 **都成功过**（每次约 20 分钟）

**结论**：**不是配置问题，是账户级并发限制** —— 免费账户同时只能跑 1 个 macOS job。当时有 4 个构建排队（`apple-` 的 #12 #13 + AutoLedger 的 #2 #3），先来先服务。

**处置**：按用户选择，不取消其他仓库任务，等自然排队。

**教训**：`queued` 长时间不动时，先看**同账号其他仓库**是否也在排队 —— 这是区分「配置错」和「排队」最快的方法。配置错通常会很快失败或直接报错，而不是无限 queued。

---

### 第 4 轮 · 2026-10-19 · ✅ 骨架构建成功（首个绿灯）

**结果**：✅ **run#2 全流程成功**

```
Set up job                  ✅
Checkout                    ✅
解析构建阶段                 ✅
选择 Xcode（已安装 iOS 平台） ✅
定位工程目录                 ✅
安装 XcodeGen               ✅
生成 Xcode 工程              ✅
确保共享 scheme 存在         ✅
编译未签名 .app（archive）    ✅
打包成未签名 IPA             ✅
上传未签名 IPA               ✅  → Skeleton-ipa (7748 B)
上传未签名 APP               ✅  → Skeleton-app (8097 B)
```

**这证明了什么**：
- `macos-14` runner 可用，能拿到机器
- XcodeGen 生成工程正常，`scheme:` 声明生效
- `xcodebuild archive` 无签名构建链路通
- `ditto` + `zip -qry` 打包、`Payload/` 结构校验通
- artifact 上传通

**同时纠正一个错误判断（重要）**：

> run#2 跑的是 commit `6c61d9b`，当时 `skeleton/project.yml` 里 **`SWIFT_VERSION` 仍是 `"5.9"`**，却成功编译出了 `.ipa`。
>
> **结论：`SWIFT_VERSION: "5.9"` 在 Xcode 26 上并不会报错。** 之前审计报告「5.9 必然失败」的判断不成立 —— 那是基于「只接受 4.0/4.2/5.0/6.0」的旧认知，Xcode 26 实际接受 `5.9`。
>
> 已改成 `"5.0"` 仍然合法（Swift 5 语言模式），不影响正确性，保留即可。但**这条记录要留着**：以后不要因为看到 `5.9` 就断定会挂，先跑一次看真实结果。

**教训**：
- **静态审计的结论也要验证**。审计员没有编译器，它的推断在「API 可用性」这类问题上准确率有限。
- **骨架工程的价值在这一刻兑现了**：它用最小成本证明了「工具链没问题」，而且顺带证伪了一条错误结论。

---

<!-- 从这里开始记录真实构建轮次 -->

---

### 第 5 轮 · 2026-10-20 · run#5–#11：四次「改 workflow」其实都在绕圈

**背景**：第 4 轮骨架绿灯之后，连续 7 次构建全部失败，但没有记录进本文件。这次重建 workflow 时顺手把 GitHub API 的真实数据拉出来补齐。

#### 构建台账（数据来源：`GET /repos/1804328/AutoLedger/actions/runs`）

| run | commit | stage | runner | 结果 | 耗时 | 失败步骤 |
|---|---|---|---|---|---|---|
| #2 | `6c61d9b` | skeleton | **macos-26** | ✅ | 19m50s | — |
| #3 | `09eb6ee` | skeleton | macos-14 | ✅ | 22m20s | — |
| #4 | `2528531` | skeleton | macos-14 | ✅ | 12m02s | — |
| #5 | `8c2dca7` | **app** | macos-14 | ❌ | 13m09s | 编译未签名 .app（archive） |
| #6 | `fa0463c` | app | macos-14 | ❌ | 2m56s | 确保共享 scheme 存在 |
| #7 | `79b6499` | app | macos-14 | ❌ | 0m27s | 校验共享 scheme 已生成 |
| #8 | `c97724e` | app | macos-14 | ❌ | 0m24s | 校验共享 scheme 已生成 |
| #9 | `349797f` | app | macos-14 | ❌ | 4m44s | 编译未签名 .app（archive） |
| #10 | `99d8c7b` | — | — | ❌ | 0m00s | workflow 文件是 0 字节 |
| #11 | `952d226` | app | **macos-26** | ❌ | 3m46s | 编译未签名 .app（archive） |

#### ❌ 证伪一条：「objectVersion 77 → 必须 macos-26」（`99d8c7b` 的结论）

这条是我在重建 workflow 时先按 commit message 写进注释、事后才被数据推翻的。三条反证：

1. **run#5 在 macos-14 上真正编译了 13m09s**。pbxproj 若真读不了，会在秒级失败，不可能编十几分钟。
2. **run#9 在 macos-14 上 step 8（`xcodebuild -list`）是绿的** —— 这一步就是拿镜像里的 Xcode 去解析生成的 `.xcodeproj`。能列出 scheme，说明工程格式读得懂。
3. **run#11 换到 macos-26，失败步骤没变、耗时几乎没变（3m46s vs 4m44s）**。换 runner 没有影响结果。

> **而且这条改法本身就违反了分诊表下面那条核心判据**：「骨架绿、主工程挂 = 代码问题，别去改 workflow。」
> 骨架在 #2/#3/#4 连绿三次，主工程从 #5 起一直挂 —— 从 #5 那一刻起就该判定 C 类，直接去读 build.log。
> #6/#7/#8/#9 四轮里有三轮在修 scheme 校验步骤（把阻塞改成诊断），那是在修**症状的显示方式**，不是在修编译错误。

**教训：连续同一步骤失败时，先问「失败点和耗时有没有随我的改动而变化」。** #7/#8 只跑 24–27 秒就挂，和 #5/#9 跑几分钟才挂，是两类完全不同的失败；把它们当成同一个问题连改四轮，就是没做这个区分。

#### ⚠️ 事故：workflow 文件被清空，且清空状态被 commit 固化

`99d8c7b` 那次改动用 PowerShell `ReadAllText` 读 workflow 失败拿到 `null`，随后 `WriteAllText(null)` 把整个文件写成 0 字节 —— 于是那次 commit message 里描述的 macos-26 改动**从来没进过文件内容**（`git show HEAD:.github/workflows/build-ipa.yml` 是 0 字节）。

两个额外坑：
- **`git status` 干净不等于文件没问题**。空文件已经被提交，工作区当然没有改动，看不出异常。改完关键文件要断言非空：`test -s <file>`。
- **`.backup` 也是坏的**。`build-ipa.yml.backup` 是 UTF-8 被按 GBK 往返读写后的乱码，拿来恢复只会恢复出乱码注释 —— 这也是本次没有用备份、而是从 `349797f` 恢复的原因。

第 2 轮已经写过「不要用 PowerShell 批量改正则」，这次的补充是：**同一套 `ReadAllText/WriteAllText` 连单文件读写都会把文件清掉，PowerShell 根本不该出现在这条链路上。** 改 Swift / YAML 一律用编辑工具做精确替换。

#### 本轮改动（1 处）

`build-ipa.yml`：删掉坑 6 里 objectVersion 的因果判断，改成「macos-26 由隔壁 `apple-` 仓库 run#10–#13 四次绿灯证明可用；macos-14 也编到过 archive，失败与 runner 无关」。

#### 关于 macos-26 的 runner 可用性（修正第 1、3 轮）

第 1 轮写「macos-26 在公开仓库长期拿不到 runner」，第 3 轮已怀疑是账户级并发限制。现在有两个独立佐证：

- **run#2 本身就是 macos-26 且成功**（19m50s，见上表）—— 当时就被误判成 macos-14 了。
- 同账号 `apple-` 仓库用 `runs-on: macos-26` + `-ge 26` 门槛，run#10–#13 全部 success。

所以第 1 轮那条「macos-14 最稳、macos-26 拿不到机器」的结论不成立，已从 workflow 注释里清除。

---

### 第 6 轮 · 待办 · 真正的拦路虎还没看过一眼

**现状**：run#5 / #9 / #11 三次都在 archive 步骤因同一类代码错误失败，但**我们至今没有读过任何一条真实 `error:`**。

**为什么读不到**：workflow 早就把错误写进了 Job Summary（`fa0463c` 的初衷是「公开可读、不用下载需鉴权的日志包」），但实测两条路都不通 ——
- 未登录浏览器打开 job 页面，日志区和 Job Summary 面板**根本不渲染**（页面只剩步骤名列表）；
- `GET /actions/runs/{id}/logs` 匿名访问返回 **403**；
- annotations API 只给了 `Process completed with exit code 1.`（step 日志第 4236 行），没有错误正文。

> **`fa0463c` 想要的「公开可读」实际上没有实现。** Job Summary 只对已登录访客可见，和它想避开的日志包权限模型是同一套。

**下一步二选一**（别两边都做）：
1. **登录 GitHub 打开** [run#11 的 job 页面](https://github.com/1804328/AutoLedger/actions/runs/39377209064/job/118477926173)，读 Job Summary 里的 `error:` 列表 → 按分诊表 C 类逐条修 Swift。**成本最低，优先做这个。**
2. 若还想让未登录也能看，就把 `summarize()` 里的错误行同时用 `::error::` workflow 命令打出来（annotations API 匿名可读）。代价是每次失败要重新烧一轮构建。

**注意**：run#11 有一条 notice —— `Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times.`。排队久是全局容量问题，不是配置问题，参考第 3 轮处置。

---

### 第 7 轮 · 2026-10-20 · ✅ 拿到第一条真实 error: —— 是 C 类

**怎么拿到的**：登录后用浏览器读 run#11 的 Job Summary（未登录时该面板不渲染，日志 API 403，见第 6 轮）。

**报错只有一条**，全项目首次出现真实编译器错误：

```
AutoLedger/Intents/AutoLedgerIntents.swift:204:9: error:
cannot convert value of type '[AppShortcut]' to expected argument type 'AppShortcut'
```

**分类**：C（自己的代码）—— 带 `file:line`，且骨架三次绿灯已排除 A 类。**这正是 run#5 / #9 / #11 卡了三轮的真正原因。**

**根因**：`AppShortcutsProvider.appShortcuts` 被 `@AppShortcutsBuilder` 标注，是**结果构建器**，不是普通数组属性。写成

```swift
static var appShortcuts: [AppShortcut] {
    [ AppShortcut(...), AppShortcut(...) ]   // ✗ 整个数组字面量被当成一个表达式
}
```

时，构建器要把 body 里的每个表达式喂给 `buildExpression(_ : AppShortcut)`，而这里只有**一个**表达式且类型是 `[AppShortcut]` → 报「数组转不成单个元素」。列号 `:204:9` 正好指向那个 `[`。

**改法**：去掉外层 `[ ]` 和元素间逗号，让每个 `AppShortcut` 各自成为一条独立语句（结果构建器写法）：

```swift
static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: AddTransactionIntent(), phrases: [...], ...)
    AppShortcut(intent: MonthSummaryIntent(),   phrases: [...], ...)
}
```

注意 `phrases:` **里面**仍是普通初始化参数，数组字面量是对的，别一起改掉。

**同类排查**：全仓只有这一个 `AppShortcutsProvider`；`AutoLedgerIntents.swift:16` 的 `caseDisplayRepresentations` 也是 `{ [`，但它是普通字典计算属性、不挂构建器，保持原样。

**教训**：
- **在 Apple 的 `@...Builder` 属性里，默认不要写数组字面量。** 声明类型是 `[X]` 极具误导性 —— 它只描述构建器的最终产物，不表示 body 里可以放一个数组。
- **报错的列号是免费的诊断信息。** `:204:9` 直接指到 `[`，比读整段代码快得多；之前四轮都在猜，一次都没看过这个数。
- 本轮只改 1 处（铁律 1），改完即构建（铁律 3）。若还有后续错误，那将是本轮之后才暴露的新错误，不要提前改。

