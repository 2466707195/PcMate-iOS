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
            // 不撑满时给足左右留白，别让文字顶到胶囊边上（看上去像溢出）
            .padding(.horizontal, expands ? 0 : 16)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: height)
            // 关键：整块玻璃都可以点，而不是只有中间的文字
            .contentShape(Rectangle())
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

// MARK: - 统一玻璃底
//
// 所有按钮都是**无色透明玻璃**：不染任何品牌色，只留材质、白色高光边和一圈中性描边。
// 层级靠文字颜色和字重区分（主 = 深品牌字，次 = 品牌字，危险 = 玫瑰字）。

private extension View {

    /// 主 / 次 / 危险按钮共用的玻璃底。
    func auroraNeutralGlass(_ shape: some Shape, shadowRadius: CGFloat = 4) -> some View {
        auroraGlassSurface(
            shape,
            tone: Aurora.inkSoft,
            tint: 0,
            border: 0.16,
            shadowRadius: shadowRadius,
            shadowY: shadowRadius > 0 ? 1 : 0
        )
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
            .auroraNeutralGlass(AuroraShape.button, shadowRadius: 5)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// 次按钮：同一块玻璃，品牌色字。
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
            .foregroundStyle(Aurora.brand)
            .auroraNeutralGlass(AuroraShape.button, shadowRadius: 3)
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
            .auroraNeutralGlass(AuroraShape.button, shadowRadius: 6)
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
    /// 默认 38pt；一行塞四个的时候传 34，看上去更紧凑
    var height: CGFloat = AuroraMetrics.smallButtonHeight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuroraButtonLabel(
                text: text,
                systemIcon: systemIcon,
                height: height,
                font: AuroraFont.labelMedium,
                expands: expands
            )
            .foregroundStyle(Aurora.brand)
            .auroraNeutralGlass(
                RoundedRectangle(cornerRadius: 13, style: .continuous),
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
            .foregroundStyle(Aurora.rose)
            .auroraNeutralGlass(AuroraShape.button, shadowRadius: 3)
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
