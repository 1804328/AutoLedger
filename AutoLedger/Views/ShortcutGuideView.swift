import SwiftUI
import UIKit

// MARK: - 快捷指令配置指南

struct ShortcutGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    quickStart
                    urlSection
                    autoSection
                    voiceSection
                    tipSection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("自动化记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("三种自动记账方式")
                .font(.headline)
            Text("装好 App 后，「快捷指令」里已经自动出现「自动记账」的两个动作，不需要手动配置。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.accent.opacity(0.1))
        )
    }

    // MARK: 方式一

    private var quickStart: some View {
        stepCard(
            number: 1,
            title: "直接对 Siri 说",
            body: "长按侧边按钮唤醒 Siri，说：\n「用自动记账记一笔」\n然后说出内容，比如「早餐 12 块」。\n\nSiri 会自动识别金额、分类和日期，直接入账，不用打开 App。"
        )
    }

    // MARK: 方式二

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(number: 2, title: "用 URL Scheme（最灵活）")

            Text("在任何支持打开链接的地方（快捷指令、其他 App、小组件）调用这个链接即可记账：")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            urlRow(
                title: "一句话记账",
                url: "autoledger://add?text=早餐12元"
            )
            urlRow(
                title: "指定金额和分类",
                url: "autoledger://add?amount=25&kind=expense&category=交通&note=打车"
            )
            urlRow(
                title: "记一笔收入",
                url: "autoledger://add?amount=8000&kind=income&category=工资&note=月薪"
            )
            urlRow(
                title: "查询本月收支",
                url: "autoledger://summary"
            )

            Text("支持的参数：text（自然语言）、amount（金额）、kind（expense/income）、category（分类名）、note（备注）、book（账本名）")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func urlRow(title: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = url
                    copied = url
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copied == url { copied = nil }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied == url ? "checkmark" : "doc.on.doc")
                        Text(copied == url ? "已复制" : "复制")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.accentDeep)
                }
                .buttonStyle(.plain)
            }
            Text(url)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: 方式三

    private var autoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(number: 3, title: "做成全自动（推荐）")

            Text("在「快捷指令」App 里新建一个自动化，让系统在特定时机自动记账：")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            autoRow(icon: "creditcard.fill", title: "收到付款通知时", detail: "自动化 → 收到付款 → 添加「自动记账」动作")
            autoRow(icon: "app.badge.fill", title: "打开某个 App 时", detail: "例如打开外卖 App 后弹一下记账")
            autoRow(icon: "clock.fill", title: "每天固定时间", detail: "每晚 22:00 提醒补记当天支出")
            autoRow(icon: "hand.tap.fill", title: "轻点背面", detail: "设置 → 辅助功能 → 轻点背面 → 选快捷指令")
            autoRow(icon: "square.grid.2x2.fill", title: "加到主屏幕/小组件", detail: "快捷指令可以放桌面，一点即记")

            Divider()

            Text("提示：iOS 不允许 App 读取其他 App 的支付数据，所以「自动」的最佳实践是：把记账动作挂到系统事件上，一句话或一次点击完成，不用手填表单。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func autoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentDeep)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 语音

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持的说话方式")
                .font(.headline)
            Text("金额、分类、日期都能听懂，中文数字也支持：")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                example("早餐豆浆油条 12 块")
                example("打车 25 元")
                example("昨天超市买了 86.5")
                example("星巴克咖啡三十二")
                example("房租 3000")
                example("工资到账 8000")
                example("3 天前加油 400")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func example(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "quote.opening")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
            Spacer()
        }
    }

    private var tipSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(Theme.accentDeep)
            Text("分类会越用越准：你手动改过一次分类后，同样的商家下次会自动归到对的地方。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent.opacity(0.1))
        )
    }

    // MARK: 组件

    private func stepCard(number: Int, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader(number: number, title: title)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func stepHeader(number: Int, title: String) -> some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "1F2B33"))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.accent))
            Text(title)
                .font(.headline)
        }
    }
}
