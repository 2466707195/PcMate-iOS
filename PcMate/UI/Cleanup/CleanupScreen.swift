import SwiftUI

struct CleanupScreen: View {

    let session: SessionController
    let hostInfo: HostInfo?

    @Environment(\.dismiss) private var dismiss
    @State private var selected: CleanupMode?
    @State private var running = false
    @State private var result: CleanupResult?
    @State private var errorMessage: String?
    @State private var showLog = false

    private var modes: [CleanupMode] {
        CleanupMode.modes(for: hostInfo?.os ?? .unknown)
    }

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: "清理内存",
                    subtitle: hostInfo?.os == .windows ? "Windows 工作集整理" : "Linux 缓存释放",
                    onBack: { dismiss() }
                ) {
                    EmptyView()
                }
            } content: {
                AuroraScrollView(bottomInset: 140) {
                    introCard
                    modeCard
                    if let errorMessage {
                        banner(icon: "exclamationmark.triangle.fill", text: errorMessage, color: Aurora.rose, background: Aurora.roseContainer)
                    }
                    if let result {
                        resultCard(result)
                    }
                }
            } bar: {
                GlassBar {
                    if result != nil {
                        PrimaryButton(text: "完成", systemIcon: "checkmark") {
                            dismiss()
                        }
                    } else {
                        GradientButton(
                            text: running ? "正在清理…" : "开始清理",
                            systemIcon: "sparkles",
                            enabled: !running && selected != nil
                        ) {
                            run()
                        }
                    }
                }
            }
        }
        .onAppear {
            if selected == nil { selected = modes.first }
        }
    }

    private var introCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Aurora.brandContainer)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("释放被缓存占用的内存")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Text("不会结束正在运行的程序")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }
                }
                Text(hostInfo?.os == .windows
                     ? "Windows 模式会让系统回收各进程暂时不用的工作集，通常能立刻看到可用内存上升。"
                     : "Linux 模式通过 /proc/sys/vm/drop_caches 释放页缓存和目录缓存；需要 root 或 sudo 密码。")
                    .font(AuroraFont.bodySmall)
                    .foregroundStyle(Aurora.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modeCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("清理方式")
                    .font(AuroraFont.titleMedium)
                    .foregroundStyle(Aurora.ink)

                ForEach(modes) { mode in
                    Button {
                        selected = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selected == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(selected == mode ? Aurora.brand : Aurora.outline)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(AuroraFont.labelLarge)
                                    .foregroundStyle(Aurora.ink)
                                Text(mode.subtitle)
                                    .font(AuroraFont.labelSmall)
                                    .foregroundStyle(Aurora.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected == mode ? Aurora.brandContainer.opacity(0.55) : Aurora.surfaceVariant.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected == mode ? Aurora.brand.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if running {
                    HStack(spacing: 9) {
                        ProgressView().tint(Aurora.brand)
                        Text("正在执行清理命令，请稍候…")
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func resultCard(_ result: CleanupResult) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(result.success ? Aurora.successContainer : Aurora.roseContainer)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 23))
                                .foregroundStyle(result.success ? Aurora.success : Aurora.rose)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.success ? "清理完成" : "清理未成功")
                            .font(AuroraFont.titleMedium)
                            .foregroundStyle(Aurora.ink)
                        Text(result.message.isEmpty ? "已执行清理命令" : result.message)
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    metric("清理前", Fmt.bytes(result.beforeBytes))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Aurora.muted)
                    metric("清理后", Fmt.bytes(result.afterBytes))
                }

                if result.freedBytes > 0 {
                    Text("释放了 \(Fmt.bytes(result.freedBytes)) \(result.metricLabel)")
                        .font(AuroraFont.labelMedium)
                        .foregroundStyle(Aurora.success)
                }

                if !result.log.isEmpty {
                    DisclosureGroup(isExpanded: $showLog) {
                        Text(result.log)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Aurora.inkSoft)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    } label: {
                        Text("查看命令输出")
                            .font(AuroraFont.labelMedium)
                            .foregroundStyle(Aurora.brand)
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AuroraFont.labelSmall)
                .foregroundStyle(Aurora.muted)
            Text(value)
                .font(AuroraFont.titleMedium)
                .foregroundStyle(Aurora.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Aurora.surfaceVariant.opacity(0.7)))
    }

    private func banner(icon: String, text: String, color: Color, background: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
    }

    private func run() {
        guard let selected, !running else { return }
        running = true
        errorMessage = nil
        result = nil
        Task { @MainActor in
            do {
                result = try await session.cleanup(mode: selected)
            } catch {
                errorMessage = error.localizedDescription
            }
            running = false
        }
    }
}
