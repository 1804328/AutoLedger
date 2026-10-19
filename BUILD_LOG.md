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

<!-- 从这里开始记录真实构建轮次 -->
