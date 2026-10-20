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

**结果**：✅ **run#12（`9526b22`，macos-26，stage=app）全流程成功，84 秒**。这是主工程第一个绿灯，也是项目首次产出可用的未签名 IPA。

| run | 步骤 | 耗时 | 产物 |
|---|---|---|---|
| #12 | 编译未签名 .app（archive） | 59s | — |
| #12 | 打包成未签名 IPA | 0s | — |
| #12 | 上传未签名 IPA | 2s | `AutoLedger-ipa` 535 KB |
| #12 | 上传未签名 APP | 0s | `AutoLedger-app` 550 KB |

> **一条错误卡了三轮构建**（run#5 13m09s、run#9 4m44s、run#11 3m46s）。修掉之后整个 app 编译只花 59 秒 —— 因为错误发生在类型检查阶段，一旦通过，剩下的都是正常编译。
>
> **反证了铁律 2「先分类再动手」的价值**：从 run#5 起「骨架三连绿 + 主工程挂」的判据已经明确指向 C 类，但中间三轮去改了 workflow。如果 run#5 当时就读 error:，能省下约 25 分钟额度。

**下一步不在本日志范围内**：产物完全未签名，需要 Sideloadly / AltStore / 自签证书处理后才能装到 iPhone。免费 Apple ID 签名只有 7 天有效、且重签会清空本地账本数据（见 workflow 顶部坑 2），装机前先确认备份路径可用。

---

### 第 8 轮 · 2026-10-20 · ✅ 真机验收：两个 App Shortcut 已注册进系统

run#12 的 IPA 签名装到 iPhone（iOS 27）后，「快捷指令」App 里能看到 **「记一笔」** 和 **「本月收支」**。

这两个字符串和 `AutoLedgerIntents.swift` 里 `appShortcuts` 的 `shortTitle` **逐字对应**：

```swift
AppShortcut(intent: AddTransactionIntent(), ..., shortTitle: "记一笔",   ...)
AppShortcut(intent: MonthSummaryIntent(),   ..., shortTitle: "本月收支", ...)
```

所以第 7 轮那次修改不只是「编译过了」，而是**编译 → 打包 → 签名 → 安装 → iOS 系统注册**整条链路都验通了。App Intents 这条最容易「静默失效」的能力（构建成功但系统里没入口）已确认有效。

#### 之前那句「快捷指令里没有自动记账」的定论

当时的判断方向是对的：不是代码问题。构建侧证据 —— 从产物 IPA 里解出 `Metadata.appintents/` 下 `extract.actionsdata`、`nlu/nlu.lzfse`、`version.json` 三个文件齐全，`title` 字段读出来是「快速记一笔」。**元数据完整，说明包内没问题。**

真实原因是入口位置和索引时机两件事叠在一起：

- **入口位置**：系统注册的是**动作名**（`shortTitle`：记一笔 / 本月收支），不是 App 名「自动记账」。在快捷指令首页顶部按 App 名找是找不到的，要在动作搜索里搜「记一笔」。
- **索引时机**：`AppIntents` 元数据由系统后台索引入库，刚装完那几分钟常常搜不到。

**教训**：判断「App Intents 有没有生效」，看 IPA 里的 `Metadata.appintents/` 是否齐、`extract.actionsdata` 里 `title` 有没有值，比在手机上反复翻界面快得多。包内齐备 + 设备端没入口，才轮到怀疑索引延迟。

#### 仍然没验的（按风险排序）

1. **数据持久化**：记一笔 → 杀掉 App → 重开，账还在不在。免费证书 7 天到期后重签会清空容器，这条必须先在手机上确认过，否则一周后一起丢。
2. **备份 / 恢复闭环**：设置 → 数据 → 备份全部数据，再用同一个 JSON 恢复。重签流程依赖它。
3. **自然语言解析的实际命中率**：`NaturalParser` 中文数字 / 商户关键词只有代码，没有测试，也没在真机上跑过样例。
4. **零测试文件**：三个纯逻辑模块（`NaturalParser`、`ChineseNumber`、`MerchantRuleEngine`）适合加单测，但它们只能在 Xcode test target 里跑，Windows 侧构建链路带不了 —— 属于「有 Mac 之后再做」。

---

### 第 9 轮 · 2026-10-20 · 解析器改造，**已提交未构建**

改动只在 `Parser/NaturalParser.swift`（+98/−4，提交 `704fd73`，带 `[skip ci]` **未推送**）。

**为什么改**：`extractAmount` 直接在原文上取第一个命中，于是日期/时间/订单号里的数字会被当成金额。手打短句不一定踩到（带「块/元」会先命中单位档），但**截图 OCR 和通知正文里全是数字**，这条不修，第 8 轮之后想做的「截图 → 自动化 → 入账」链路会稳定记错金额。

顺带纠正两条 README 的失真宣称：「3 天前加油 400」旧版实际记成 **3 元**；「星巴克咖啡三十二」旧版 **取不到金额**（中文数字档强制要求带单位）。

**四项改动**：

1. `maskNoiseNumbers` —— 取金额前把日期、`HH:mm[:ss]`、4 位以上年份、**8 位以上长数字**（订单号/卡号/手机号）替换成**等长空格**。等长是硬约束：`AmountHit.span` 要能原样映射回 `text` 供备注提取用，长度一变 span 就指错位置。
2. 新增 **0 档账单锚点**（实付/已付款/合计/消费/金额…）排在带符号档之前 → 「优惠¥5.00 实付¥31.00」取 31，旧逻辑取 5。
3. 新增 **4 档无单位中文数字兜底**，仅当全文无阿拉伯数字时启用，且要求命中串带位数词或≥2 字。星期表达式已在屏蔽表里，所以「周一开会打车二十」不会被读成 1 元。
4. 备注清洗复用同一张屏蔽表，并补 `支付成功 / 支付宝 / 账户余额 / 零钱` 等噪声词。`noteNoise` **顺序敏感**：复合词必须排在构成它的短词之前，否则「支付宝」被「支付」拆成「宝」、商户匹配直接失效。

**怎么验的（Windows 上没有 swiftc）**：把整条分档流水线 + `ChineseNumber.parse` 忠实移植成 Python，按同序跑 31 个用例（README 宣称的 6 条 + OCR 真实页面 + 对抗性排序用例），全过；`mask` 里加了断言强制长度不变，直接守第 1 条那个隐式不变量。脚本：`probe/parser_check.py`（本地，未入库）。
移植只能证明**正则语义和分档顺序**，证明不了 Swift 语法。已知踩过的坑：`NSString` 没有 `rangeOfCharacter(from:)`，写成 `masked.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })`。

**已知局限（不是 bug）**：账单**汇总页**截图（「本月已消费¥12,345.00」）会被锚点档当成一笔消费入账。这条留给快捷指令侧过滤——自动化里判断文本含「支付成功/付款成功」才继续。

**下一轮构建时**：如果挂，C 类错误大概率集中在 `NaturalParser.swift` 的新增正则/类型上，按 `file:line` 定位即可，别动 workflow（铁律 2）。去重（同一时间窗同金额同商户）留给下一轮，因为那要改 `LedgerStore` 的写入路径，属于持久化，不能和本轮解析逻辑混在一起排查。

---

### 第 10 轮 · 2026-10-20 · 截图 OCR 入账 + 自动入账去重，**代码完成，未构建**

用户把这轮整条交出来（「全部交给你来弄好」）。方向因此改变：不再教用户在快捷指令里搭六个动作块，而是**把能力做进 App**——装完就有入口，零装配。

#### 新增 / 改动（2 个新文件 + 5 处改动）

- **`Parser/ReceiptOCR.swift`（新建）**：Vision `VNRecognizeTextRequest`，`recognitionLevel = .accurate`、`recognitionLanguages = ["zh-Hans", "en-US"]`。按阅读顺序输出文本行再拼成一行喂给 `NaturalParser`——**顺序是功能不是美化**：兜底档取第一个命中，乱序就会取到余额。Vision 归一化坐标原点在左下角，所以「靠上」= `midY` 大，同一行用 0.02 容差再按 x 排。本机识别，不联网、不上传。
- **`Views/ReceiptScanSheet.swift`（新建）**：`PhotosPicker` 选一张截图。**选它而不是相册读取，是为了整条路径不需要相册权限声明**。预览 → 识别中 → 金额/分类/日期标签 → 「纠正分类」→ 入账；被去重拦下时给一条「仍然入账」的出口。
- **`Views/HomeView.swift`**：右上角加 `camera.viewfinder` 工具栏入口 + sheet。
- **`Models/Models.swift`**：`TxSource` 增 `case screenshot`（「截图识别」，图标 `camera.viewfinder`）。全仓只有两处 `TxSource` 的穷尽 switch（已 grep 确认），加 case 安全；`Codable` 走 rawValue，旧数据不受影响。
- **`Store/LedgerStore.swift`**：`addAutomated(_:)` —— 同账本 + 同收支类型 + 同金额 + **60 秒内**已有则跳过并返回 nil。只对机器来源生效，`.manual` / `.imported` 直接豁免（连买两杯奶茶是真事，不能吞）。周期账生成走 `transactions.append` + 自己的 fingerprint 判重，不经过这条路。
- **`Intents/AutoLedgerIntents.swift`**：`AddTransactionIntent` 与 `URLRouter` 两个分支都换成 `addAutomated`，被去重时明确回话，不静默吞掉一笔。
- **`Views/ShortcutGuideView.swift`**：新增「截图入账」卡（方式三），原「做成全自动（推荐）」降级为方式四。

#### 顺手修掉的一条虚假宣称

原指南里这行是不存在的触发条件：

```swift
autoRow(icon: "creditcard.fill", title: "收到付款通知时", detail: "自动化 → 收到付款 → 添加「自动记账」动作")
```

而且用户的反驳本身成立：**支付成功通常不产生系统通知**，通知在支付环节根本指望不上。已替换成 iOS 27 实际存在的时机（截屏、轻点背面、收到通知时——并注明只适合确实弹通知的银行扣款提醒、打开 App、定时、主屏幕）。

同一段那句「iOS 不允许 App 读取其他 App 的支付数据」重写成能做到的上限：**系统帮你抓一张截图或一段屏幕文字，识别和入账由 App 完成；省掉的是「打开 App 填表单」，不是「支付」这一步**。`intro` 里「快捷指令里已经自动出现**自动记账**的两个动作」也按第 8 轮实测改成动作名「记一笔」「本月收支」，并提示按动作名搜。

#### 一次避免掉的构建浪费

原计划给 `AddTransactionIntent` 加一个图片类型的 `@Parameter`，让快捷指令直接把截图传进来。查到 `Intents.ImageContent` 文档页 404——**SiriKit 在 iOS 27 已废弃**，`ImageContent` 属于那一族。拿它当参数有较大概率编译失败，而一次失败就是几十分钟 macOS 额度。改成：快捷指令侧用系统动作「提取图像中的文本」得到纯文本 → 喂 `text` 参数；需要图片识别的场景走 App 内的 `ReceiptScanSheet`。效果一样，风险归零。**这条判断没有编译器背书，属于「不确定就不赌」。**

#### 没验过的

Windows 上没有 swiftc，本轮代码**一行都没编译过**。Python 移植能验解析语义，验不了 Vision API 用法和 SwiftUI 修饰符顺序。真机重点：

1. `PhotosPicker` 取到的截图 `UIImage` 是否带方向信息，导致 `cgImage` 出来是躺着的、OCR 空结果。
2. `.accurate` + 整屏截图的耗时，UI 上会不会看起来像卡死。
3. 60 秒窗口是否过宽：手动记 25 后马上用截图记 25 会被跳过——界面上有「仍然入账」出口，快捷指令和 URL 只有回话、没有出口。

第 11 轮如果挂，C 类错误优先怀疑 `ReceiptScanSheet.swift` 的类型推断与 `ReceiptOCR.swift` 的 Vision 调用。`project.yml` 里 `sources: - path: AutoLedger` 是递归的，**新增 Swift 文件不需要改工程配置、不需要重新生成 `.xcodeproj`**。

---

### 第 11 轮 · 2026-10-20 · ✅ run#13 绿灯：第 9+10 轮代码一次通过编译

远端 `main` 从 `4b8e4b8` 推到 `9bcc566`（5 个提交：第 8/9/10 轮的台账 + 解析器改造 + OCR/去重）。

**run#13**（`workflow_dispatch`，stage=app，configuration=Release，`39388335133`）**全绿**：`生成 Xcode 工程 → 编译未签名 .app（archive） → 打包成未签名 IPA → 上传` 12 个实质步骤全部 success，产物 `AutoLedger-ipa` 581 KB / `AutoLedger-app` 599 KB，墙钟 1m47s。

也就是说第 10 轮那句「一行都没编译过」的顾虑**没有变成错误**：`VNRecognizeTextRequest` 的用法、`PhotosPicker` + `loadTransferable`、`TxSource` 加 case、`addAutomated` 返回 `Transaction?`、SwiftUI 那边的 `if let scan` 简写和 `.primaryButtonStyle()` 修饰顺序，在 macos-26 / Xcode 26 上全部成立。**结论：Windows 侧「定界符平衡 + 逐个 API 存在性自查 + Python 移植验语义」这套替代验证，在这两轮里足够用了**，没有出现需要靠编译器才能发现的错误。

#### 这轮踩到的一条新坑：`[skip ci]` 看的是 tip 提交

推送后 **Actions 一个 run 都没出现**。原因：这批里最后一个提交 `9bcc566` 是文档提交、带 `[skip ci]`，GitHub 对 push 事件按 **tip 提交的消息**判定跳过——**前面那个不带标记的 `788c1ae feat(ocr)` 完全不起作用**。

后果很隐蔽：代码确实推上去了（远端 HEAD 就是新提交），但构建静默不发生，从手机侧看就是「改了没生效」。

**做法改成两条**：
1. 攒批推送时，把**不带 `[skip ci]` 的提交排在最后**（`git commit` 顺序即可，不必 rebase）。
2. 已经推错了就手动派发。**注意 `workflow_dispatch` 的 `stage` 下拉默认是 `skeleton`**，而 push 事件的默认值走 `env.STAGE` 才是 `app`——手点时不改成 `app` 就只构建骨架，白等两分钟。本轮就是把 stage 手动改成 app 才构建正式包。
3. `on.push.paths` 只认 `AutoLedger/**`、`skeleton/**`、`project.yml`、workflow 文件本身；**根目录的 `BUILD_LOG.md` / `README.md` 改动不会触发构建**，空提交也不会（没有文件变更，paths 匹配不上）。

#### 认证侧的一次性配置（以后不用再管）

`origin` 是 `ssh://git@ssh.github.com:443/...`。本机 `~/.ssh/id_rsa.pub` 之前没注册到账号，`Permission denied (publickey)`；把公钥加进 GitHub Settings → SSH and GPG keys 后 `ssh -T` 回 `Hi 1804328!`，推送即通。**HTTPS 那条路仍是坏的**：git 全局 `http.proxy` 指向一个没在跑的 `127.0.0.1:62199`，且 GCM 里存的是已废弃的用户名+密码。别再退回 HTTPS 试。

#### 现在该做的（按顺序）

1. 下 `AutoLedger-ipa` → 用免费 Apple ID 重签装机。**重签会清空沙盒数据，所以装新包之前先跑一次备份**。
2. 装完先验第 10 轮那条运行时风险：`PhotosPicker` 取到的截图是否因为 `imageOrientation` 导致 OCR 空结果——这是唯一一类编译过但真机不工作的错。
3. 第 8/10 轮列的数据持久化、备份恢复闭环仍未验，且必须在第一次重签之前验。
