import SwiftUI

// === Aurora UI 按钮（iOS / SwiftUI）===
// 硬规则：按钮文字必须居中 —— 统一用 Button + 居中的 label，
// 不要自己拼 HStack 挤文案。

/// 按钮文字：图标 + 文案，整体水平垂直居中。
///
/// - `expands`: 是否撑满父容器宽度。
///   主按钮（底部操作条里成对出现的那种）用 `true`；
///   列表行里的小按钮用 `false`，否则会抢掉整行的空间。
struct AuroraButtonLabel: View {

    let text: String
    var systemIcon: String? = nil
    var height: CGFloat = AuroraMetrics.primaryButtonHeight
    var font: Font = AuroraFont.labelLarge
    var expands: Bool = true

    var body: some View {
        content
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: height)
    }

    private var content: some View {
        HStack(spacing: 6) {
            if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(text)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .fixedSize(horizontal: !expands, vertical: false)
    }
}

/// 主按钮：品牌色**玻璃**底 + 深品牌字。
///
/// 不再用实心填充 —— 整块玻璃透出底下的极光背景，靠染色强度和描边体现层级。
struct PrimaryButton: View {

    let text: String
    var systemIcon: String? = nil
    var enabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuroraButtonLabel(
                text: text,
                systemIcon: systemIcon,
                expands: expands
            )
            .foregroundStyle(Aurora.brandDeep)
            .auroraGlassSurface(
                AuroraShape.button,
                tone: Aurora.brand,
                tint: 0.20,
                border: 0.45,
                shadowRadius: 4,
                shadowY: 1
            )
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// 次按钮：浅玻璃 + 品牌字。
struct TonalButton: View {

    let text: String
    var systemIcon: String? = nil
    var enabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuroraButtonLabel(
                text: text,
                systemIcon: systemIcon,
                expands: expands
            )
            .foregroundStyle(Aurora.brandDeep)
            .auroraGlassSurface(
                AuroraShape.button,
                tone: Aurora.brand,
                tint: 0.07,
                border: 0.16,
                shadowRadius: 3,
                shadowY: 1
            )
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// 主 CTA：品牌**渐变玻璃**底。禁用时自动降透明度。
///
/// 一个页面最多一个。
struct GradientButton: View {

    let text: String
    var systemIcon: String? = nil
    var enabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuroraButtonLabel(
                text: text,
                systemIcon: systemIcon,
                expands: expands
            )
            .foregroundStyle(Aurora.brandDeep)
            .auroraGlassSurface(
                AuroraShape.button,
                tone: Aurora.brand,
                tint: 0.28,
                border: 0.55,
                shadowRadius: 5,
                shadowY: 2
            )
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }
}

/// 小按钮（38pt 高，13pt 圆角），同样走玻璃。
struct SmallTonalButton: View {

    let text: String
    var systemIcon: String? = nil
    var enabled: Bool = true
    var expands: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuroraButtonLabel(
                text: text,
                systemIcon: systemIcon,
                height: AuroraMetrics.smallButtonHeight,
                font: AuroraFont.labelMedium,
                expands: expands
            )
            .foregroundStyle(Aurora.brandDeep)
            .auroraGlassSurface(
                RoundedRectangle(cornerRadius: 13, style: .continuous),
                tone: Aurora.brand,
                tint: 0.07,
                border: 0.18,
                shadowRadius: 0
            )
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// 危险操作按钮（玫瑰色玻璃）。
struct DangerTonalButton: View {

    let text: String
    var systemIcon: String? = nil
    var enabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuroraButtonLabel(
                text: text,
                systemIcon: systemIcon,
                expands: expands
            )
            .foregroundStyle(Aurora.onRoseContainer)
            .auroraGlassSurface(
                AuroraShape.button,
                tone: Aurora.rose,
                tint: 0.10,
                border: 0.28,
                shadowRadius: 3,
                shadowY: 1
            )
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// 文字按钮（对应 Material 的 TextButton）。
struct TextLinkButton: View {

    let text: String
    var systemIcon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(text)
                    .font(AuroraFont.labelMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(Aurora.brand)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
