import SwiftUI

// === Aurora UI 设计 token（iOS / SwiftUI）===
// 与 Android 版 `ui/theme/Theme.kt` 一一对应，数值完全一致。

/// `Aurora` 里的每一个色值都是**计算属性**，实时从 `ThemeRuntime.palette` 取。
/// 用户改主题 → `ThemeStore.config` 变化 → 调色板重算 → 界面重绘时读到新色。
/// 千万别改回 `static let`，那样换主题不会生效。
enum Aurora {

    private static var palette: AuroraPalette { ThemeRuntime.palette }

    // MARK: - 品牌三色

    static var brand: Color { palette.brand }              // 主色：主按钮、选中态、强调文字、进度条
    static var brandDeep: Color { palette.brandDeep }      // 渐变起点、按下态
    static var teal: Color { palette.teal }                // 正常/成功的辅助色
    static var rose: Color { palette.rose }                // 提醒、警示、删除类操作

    // MARK: - 中性色

    static var canvas: Color { palette.canvas }            // 画布
    static var surface: Color { palette.surface }          // 卡片（**不透明**）
    static var ink: Color { palette.ink }                  // 主文字
    static var inkSoft: Color { palette.inkSoft }          // 次文字
    static var line: Color { palette.line }                // 描边
    static var surfaceVariant: Color { palette.surfaceVariant }
    static var outline: Color { palette.outline }

    // MARK: - 容器色（Material 3 primary/secondary/tertiary container）

    static var brandContainer: Color { palette.brandContainer }
    static var onBrandContainer: Color { palette.onBrandContainer }
    static var tealContainer: Color { palette.tealContainer }
    static var onTealContainer: Color { palette.onTealContainer }
    static var roseContainer: Color { palette.roseContainer }
    static var onRoseContainer: Color { palette.onRoseContainer }

    // MARK: - 语义色（M3 之外额外需要的）

    static var success: Color { palette.success }
    static var successContainer: Color { palette.successContainer }
    static var warning: Color { palette.warning }
    static var warningContainer: Color { palette.warningContainer }
    static var info: Color { palette.info }
    static var infoContainer: Color { palette.infoContainer }
    static var muted: Color { palette.muted }
    static var hairline: Color { palette.hairline }
    static var danger: Color { palette.danger }

    // MARK: - 背景光晕

    static var glowA: Color { palette.glowA }
    static var glowB: Color { palette.glowB }
    static var glowC: Color { palette.glowC }
    static var glowStrength: Double { palette.glowStrength }
    static var isDark: Bool { palette.isDark }

    // MARK: - 渐变（仅用于主 CTA 底色）

    static var brandGradient: LinearGradient { palette.brandGradient }

    // MARK: - 阴影

    static var cardShadow: Color { palette.cardShadow }
    static var barShadow: Color { palette.barShadow }
}

// MARK: - 字阶

/// 中文优先：层级靠字重拉开，不靠字号堆叠；中文标题带负字距，视觉更紧实。
/// 负字距用 SwiftUI 的 `tracking` 表达（单位 pt，等价 Android 的 sp 偏移）。
enum AuroraFont {

    static let headlineMedium = Font.system(size: 28, weight: .bold)
    static let headlineSmall = Font.system(size: 24, weight: .bold)
    static let titleLarge = Font.system(size: 19, weight: .bold)
    static let titleMedium = Font.system(size: 16, weight: .semibold)
    static let titleSmall = Font.system(size: 14, weight: .semibold)
    static let bodyLarge = Font.system(size: 15, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .regular)
    static let bodySmall = Font.system(size: 12.5, weight: .regular)
    static let labelLarge = Font.system(size: 14, weight: .semibold)
    static let labelMedium = Font.system(size: 12, weight: .semibold)
    static let labelSmall = Font.system(size: 11, weight: .medium)
}

// MARK: - 间距与尺寸（8pt 网格）

enum AuroraMetrics {
    static let pagePadding: CGFloat = 14      // 页面左右边距
    static let cardPadding: CGFloat = 16      // 卡片内边距
    static let cardSpacing: CGFloat = 10      // 卡片间距
    static let listBottomInset: CGFloat = 168 // 列表底部留白（避开底部操作条）
    static let barBottomInset: CGFloat = 68   // 底部导航条占用的高度（含留白）
    static let primaryButtonHeight: CGFloat = 50
    static let smallButtonHeight: CGFloat = 38
    static let iconButtonSize: CGFloat = 44
}

// MARK: - 形状

enum AuroraShape {
    static let control = RoundedRectangle(cornerRadius: 14, style: .continuous) // 表单控件 / 小按钮
    static let button = RoundedRectangle(cornerRadius: 16, style: .continuous)  // 主按钮
    static let card = RoundedRectangle(cornerRadius: 20, style: .continuous)     // 卡片
    static let sheet = RoundedRectangle(cornerRadius: 24, style: .continuous)    // 弹窗
    static let bar = RoundedRectangle(cornerRadius: 26, style: .continuous)      // 底部操作条
    static let badge = RoundedRectangle(cornerRadius: 12, style: .continuous)    // 小方块
}

// MARK: - 状态等级 → 颜色

/// 1=信息 2=成功 3=警告 4=错误 其他=中性
func statusColor(_ level: Int) -> Color {
    switch level {
    case 1: return Aurora.info
    case 2: return Aurora.success
    case 3: return Aurora.warning
    case 4: return Aurora.danger
    default: return Aurora.muted
    }
}

// MARK: - 按压反馈

/// 卡片按下时轻微缩放，给实体感。
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.982

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
