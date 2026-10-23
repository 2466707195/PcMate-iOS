import SwiftUI

// MARK: - 界面主题
//
// 「设置 → 界面主题」里能改：主色（图标 / 按钮 / 强调）、背景底色、背景光晕与强度。
// 所有改动即时生效并写入 UserDefaults，下次打开 App 还是这套颜色。
//
// 实现：这里只改 `ThemeStore.config`，界面颜色由 `Aurora.*` 计算属性统一重取，
// 所以不需要在每个页面单独处理主题。

struct ThemeScreen: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeStore.shared

    private let presetColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ZStack {
            AuroraBackdrop()

            AuroraScreen {
                AppTopBar(
                    title: "界面主题",
                    subtitle: theme.themeName,
                    onBack: { dismiss() }
                ) {
                    AuroraIconButton(
                        systemIcon: "arrow.counterclockwise",
                        tone: Aurora.inkSoft
                    ) {
                        theme.reset()
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 32) {
                    previewCard
                    presetCard
                    customCard
                    aboutCard
                }
            } bar: {
                EmptyView()
            }
        }
    }

    // MARK: 预览

    private var previewCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                AuroraSectionHeader(
                    title: "预览",
                    subtitle: "改完立刻生效，不用重启",
                    systemIcon: "eye",
                    trailingText: theme.themeName
                )

                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Aurora.brand.tint(0.13))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("我的电脑")
                            .font(AuroraFont.titleSmall)
                            .foregroundStyle(Aurora.ink)
                        Text("192.168.3.252 · Agent 1.5.0")
                            .font(AuroraFont.labelSmall)
                            .foregroundStyle(Aurora.muted)
                    }

                    Spacer(minLength: 4)

                    StatusPill(text: "已连接", color: Aurora.teal)
                }

                HStack(spacing: 8) {
                    SmallTonalButton(text: "小按钮", systemIcon: "bolt.fill") { }
                    SmallTonalButton(text: "次要", systemIcon: "folder") { }

                    Spacer(minLength: 0)

                    Text("图标与文字跟随主色")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                HStack(spacing: 6) {
                    Circle().fill(Aurora.glowA).frame(width: 9, height: 9)
                    Circle().fill(Aurora.glowB).frame(width: 9, height: 9)
                    Circle().fill(Aurora.glowC).frame(width: 9, height: 9)
                    Text(theme.isDark ? "深色底 · 文字自动反色" : "浅色底 · 卡片自动实白")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    // MARK: 预设

    private var presetCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "预设",
                    subtitle: "点一下整套换掉",
                    systemIcon: "wand.and.stars"
                )

                LazyVGrid(columns: presetColumns, spacing: 8) {
                    ForEach(ThemePreset.all) { preset in
                        presetCell(preset)
                    }
                }
            }
        }
    }

    private func presetCell(_ preset: ThemePreset) -> some View {
        let selected = theme.matchedPreset?.id == preset.id
        return Button {
            theme.apply(preset)
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color(hex: preset.config.canvas))
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(Color(hex: preset.config.accent))
                        .frame(width: 24, height: 24)
                }
                .overlay(
                    Circle()
                        .stroke(
                            selected ? Aurora.brand : Aurora.outline.opacity(0.7),
                            lineWidth: selected ? 2 : 1
                        )
                        .frame(width: 44, height: 44)
                )

                Text(preset.name)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(selected ? Aurora.brand : Aurora.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Aurora.brand.tint(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 自定义

    private var customCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                AuroraSectionHeader(
                    title: "自定义",
                    subtitle: "主色、底色与背景光晕",
                    systemIcon: "slider.horizontal.3"
                )
                .padding(.bottom, 4)

                colorRow(
                    title: "主色",
                    subtitle: "图标、按钮和强调文字",
                    selection: $theme.accentColor
                )

                Divider().overlay(Aurora.hairline)

                colorRow(
                    title: "背景底色",
                    subtitle: theme.isDark ? "深色底：卡片与文字自动跟着变" : "浅色底：卡片保持实白",
                    selection: $theme.canvasColor
                )

                Divider().overlay(Aurora.hairline)

                colorRow(
                    title: "光晕颜色",
                    subtitle: "背景里那三团柔光",
                    selection: $theme.glowColor
                )

                Divider().overlay(Aurora.hairline)

                strengthRow
            }
        }
    }

    private func colorRow(title: String, subtitle: String, selection: Binding<Color>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AuroraFont.titleSmall)
                    .foregroundStyle(Aurora.ink)
                Text(subtitle)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            ColorPicker("", selection: selection, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
        }
        .padding(.vertical, 10)
    }

    private var strengthRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("光晕强度")
                        .font(AuroraFont.titleSmall)
                        .foregroundStyle(Aurora.ink)
                    Text("0 关闭 · 100% 为默认")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }

                Spacer(minLength: 8)

                Text("\(Int((theme.glowStrength * 100).rounded()))%")
                    .font(AuroraFont.labelMedium)
                    .foregroundStyle(Aurora.brand)
                    .monospacedDigit()
            }

            Slider(value: $theme.glowStrength, in: 0...1.6, step: 0.05)
                .tint(Aurora.brand)
        }
        .padding(.vertical, 10)
    }

    // MARK: 说明

    private var aboutCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                AuroraSectionHeader(
                    title: "说明",
                    subtitle: "只影响这台手机的外观",
                    systemIcon: "info.circle"
                )

                VStack(alignment: .leading, spacing: 8) {
                    tip("换主题不会同步到电脑，也不会影响连接和打印。")
                    tip("深色底色下，卡片和文字会自动反色，不用手动调。")
                    tip("右上角的 ↺ 可以一键恢复成默认的极光主题。")
                }

                TonalButton(text: "恢复默认主题", systemIcon: "arrow.counterclockwise") {
                    theme.reset()
                }
                .padding(.top, 2)
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(Aurora.brand.opacity(0.55))
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(Aurora.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
