import Foundation
import SwiftUI
import Combine

// === 主题系统 ===
//
// 用户可以在「设置 → 界面主题」里改：主色（图标 / 按钮 / 强调）、背景底色、
// 背景光晕色与强度，也可以一键套用预设。
//
// 实现方式：
//   ThemeConfig（存 UserDefaults 的原始值）
//       ↓ ThemePalette.resolve
//   AuroraPalette（解析后的全部 token）
//       ↓ ThemeRuntime.palette
//   Aurora.brand / Aurora.canvas / …（算出来的静态属性）
//
// 注意：`Aurora` 里的色值必须保持 **计算属性**，不要改回 `static let`，
// 否则换主题时界面不会重新取色。

// MARK: - 主题配置（可持久化）

struct ThemeConfig: Codable, Equatable {

    var accent: UInt32        // 主色：图标、按钮、强调文字
    var canvas: UInt32        // 背景底色
    var glowA: UInt32         // 背景光晕 1（左上）
    var glowB: UInt32         // 背景光晕 2（右侧）
    var glowC: UInt32         // 背景光晕 3（左下）
    var glowStrength: Double  // 光晕强度 0…1.6

    static let standard = ThemeConfig(
        accent: 0x4F46E5,
        canvas: 0xF8F7FC,
        glowA: 0x4F46E5,
        glowB: 0x0F9D9D,
        glowC: 0xD6336C,
        glowStrength: 1.0
    )
}

// MARK: - 预设

struct ThemePreset: Identifiable, Equatable {

    let id: String
    let name: String
    let config: ThemeConfig

    static let all: [ThemePreset] = [
        ThemePreset(
            id: "aurora",
            name: "极光",
            config: ThemeConfig(
                accent: 0x4F46E5,
                canvas: 0xF8F7FC,
                glowA: 0x4F46E5,
                glowB: 0x0F9D9D,
                glowC: 0xD6336C,
                glowStrength: 1.0
            )
        ),
        ThemePreset(
            id: "celadon",
            name: "青瓷",
            config: ThemeConfig(
                accent: 0x0E8C8C,
                canvas: 0xF4FAFA,
                glowA: 0x0E8C8C,
                glowB: 0x4F46E5,
                glowC: 0x63C7B8,
                glowStrength: 1.1
            )
        ),
        ThemePreset(
            id: "rose",
            name: "玫瑰",
            config: ThemeConfig(
                accent: 0xD6336C,
                canvas: 0xFDF6F8,
                glowA: 0xD6336C,
                glowB: 0x8B5CF6,
                glowC: 0xF2A7C0,
                glowStrength: 1.0
            )
        ),
        ThemePreset(
            id: "sunset",
            name: "日落",
            config: ThemeConfig(
                accent: 0xE4572E,
                canvas: 0xFDF8F2,
                glowA: 0xF4A259,
                glowB: 0xE4572E,
                glowC: 0xE5C07B,
                glowStrength: 1.15
            )
        ),
        ThemePreset(
            id: "forest",
            name: "森林",
            config: ThemeConfig(
                accent: 0x2E7D5B,
                canvas: 0xF4FAF6,
                glowA: 0x2E7D5B,
                glowB: 0x0F9D9D,
                glowC: 0xB7D8A8,
                glowStrength: 1.05
            )
        ),
        ThemePreset(
            id: "graphite",
            name: "石墨",
            config: ThemeConfig(
                accent: 0x8B93FF,
                canvas: 0x111118,
                glowA: 0x5B54F0,
                glowB: 0x0F9D9D,
                glowC: 0xD6336C,
                glowStrength: 1.35
            )
        )
    ]
}

// MARK: - 解析后的调色板

/// 一套完整的 Aurora token。`Aurora` 只是它的只读门面。
struct AuroraPalette {

    var isDark: Bool = false

    // 品牌三色
    var brand = Color(hex: 0x4F46E5)
    var brandDeep = Color(hex: 0x3730C0)
    var teal = Color(hex: 0x0F9D9D)
    var rose = Color(hex: 0xD6336C)

    // 中性
    var canvas = Color(hex: 0xF8F7FC)
    var surface = Color.white
    var ink = Color(hex: 0x17171F)
    var inkSoft = Color(hex: 0x5C5C70)
    var line = Color(hex: 0xE7E5F0)
    var surfaceVariant = Color(hex: 0xEFEDF7)
    var outline = Color(hex: 0xC6C3D6)
    var muted = Color(hex: 0x8A8AA0)
    var hairline = Color(hex: 0xEFEDF6)

    // 容器
    var brandContainer = Color(hex: 0xE5E2FF)
    var onBrandContainer = Color(hex: 0x1B1464)
    var tealContainer = Color(hex: 0xCAF2F1)
    var onTealContainer = Color(hex: 0x003737)
    var roseContainer = Color(hex: 0xFFD9E3)
    var onRoseContainer = Color(hex: 0x3E0021)

    // 语义
    var success = Color(hex: 0x11875A)
    var successContainer = Color(hex: 0xD8F5E8)
    var warning = Color(hex: 0xB26A00)
    var warningContainer = Color(hex: 0xFFEDCB)
    var info = Color(hex: 0x2563EB)
    var infoContainer = Color(hex: 0xDDE8FF)
    var danger = Color(hex: 0xC62828)

    // 背景光晕
    var glowA = Color(hex: 0x4F46E5)
    var glowB = Color(hex: 0x0F9D9D)
    var glowC = Color(hex: 0xD6336C)
    var glowStrength: Double = 1.0

    // 阴影
    var cardShadow = Color.black.opacity(0.05)
    var barShadow = Color(red: 0.06, green: 0.06, blue: 0.16).opacity(0.10)

    var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandDeep, brand.lightened(0.20)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - 从配置算出调色板

enum ThemePalette {

    static func resolve(_ config: ThemeConfig) -> AuroraPalette {
        var p = AuroraPalette()

        let accent = Color(hex: config.accent)
        let canvas = Color(hex: config.canvas)
        let dark = canvas.perceivedLuminance < 0.5

        p.isDark = dark
        p.canvas = canvas
        p.glowA = Color(hex: config.glowA)
        p.glowB = Color(hex: config.glowB)
        p.glowC = Color(hex: config.glowC)
        p.glowStrength = max(0, min(1.6, config.glowStrength))

        if dark {
            // 深色底：卡片比底色亮一点点，文字反白
            p.surface = canvas.lightened(0.075)
            p.surfaceVariant = canvas.lightened(0.13)
            p.ink = Color(hex: 0xF2F2F7)
            p.inkSoft = Color(hex: 0xA8A8BC)
            p.muted = Color(hex: 0x8C8CA1)
            p.line = Color(hex: 0x32323E)
            p.hairline = Color(hex: 0x282832)
            p.outline = Color(hex: 0x4C4C5E)

            p.brand = accent.lightened(0.06)
            p.brandDeep = accent.darkened(0.20)

            p.teal = Color(hex: 0x35C4C4)
            p.rose = Color(hex: 0xF2598C)

            // 深色底的「浅色容器」= 底色里掺一点主色，不是主色里掺白
            p.brandContainer = p.surface.mixed(with: accent, 0.22)
            p.onBrandContainer = accent.lightened(0.55)
            p.tealContainer = p.surface.mixed(with: p.teal, 0.20)
            p.onTealContainer = p.teal.lightened(0.55)
            p.roseContainer = p.surface.mixed(with: p.rose, 0.20)
            p.onRoseContainer = p.rose.lightened(0.55)

            p.success = Color(hex: 0x3BC48C)
            p.successContainer = p.surface.mixed(with: p.success, 0.20)
            p.warning = Color(hex: 0xE0A63C)
            p.warningContainer = p.surface.mixed(with: p.warning, 0.20)
            p.info = Color(hex: 0x6C9CFF)
            p.infoContainer = p.surface.mixed(with: p.info, 0.20)
            p.danger = Color(hex: 0xF2645C)

            p.cardShadow = Color.black.opacity(0.38)
            p.barShadow = Color.black.opacity(0.50)
        } else {
            p.surface = .white
            p.surfaceVariant = Color(hex: 0xEFEDF7)
            p.ink = Color(hex: 0x17171F)
            p.inkSoft = Color(hex: 0x5C5C70)
            p.muted = Color(hex: 0x8A8AA0)
            p.line = Color(hex: 0xE7E5F0)
            p.hairline = Color(hex: 0xEFEDF6)
            p.outline = Color(hex: 0xC6C3D6)

            p.brand = accent
            p.brandDeep = accent.darkened(0.22)

            p.teal = Color(hex: 0x0F9D9D)
            p.rose = Color(hex: 0xD6336C)

            p.brandContainer = accent.mixed(with: .white, 0.86)
            p.onBrandContainer = accent.darkened(0.60)
            p.tealContainer = p.teal.mixed(with: .white, 0.84)
            p.onTealContainer = p.teal.darkened(0.62)
            p.roseContainer = p.rose.mixed(with: .white, 0.86)
            p.onRoseContainer = p.rose.darkened(0.62)

            p.success = Color(hex: 0x11875A)
            p.successContainer = Color(hex: 0xD8F5E8)
            p.warning = Color(hex: 0xB26A00)
            p.warningContainer = Color(hex: 0xFFEDCB)
            p.info = Color(hex: 0x2563EB)
            p.infoContainer = Color(hex: 0xDDE8FF)
            p.danger = Color(hex: 0xC62828)

            p.cardShadow = Color.black.opacity(0.05)
            p.barShadow = Color(red: 0.06, green: 0.06, blue: 0.16).opacity(0.10)
        }

        return p
    }
}

// MARK: - 运行时（Aurora 从这里取值）

enum ThemeRuntime {
    static var config: ThemeConfig = .standard
    static var palette: AuroraPalette = ThemePalette.resolve(.standard)
}

// MARK: - 主题仓库

final class ThemeStore: ObservableObject {

    static let shared = ThemeStore()

    private static let storageKey = "pcmate.theme.v1"

    private var stored: ThemeConfig

    /// 改这个值会自动：重算调色板 + 通知界面重绘 + 落盘。
    var config: ThemeConfig {
        get { stored }
        set {
            guard newValue != stored else { return }
            objectWillChange.send()
            stored = newValue
            ThemeRuntime.config = newValue
            ThemeRuntime.palette = ThemePalette.resolve(newValue)
            Self.save(newValue)
        }
    }

    var palette: AuroraPalette { ThemeRuntime.palette }
    var isDark: Bool { ThemeRuntime.palette.isDark }

    /// 当前配置匹配上了哪套预设（没匹配上 = 自定义）
    var matchedPreset: ThemePreset? {
        ThemePreset.all.first { preset in
            preset.config.accent == stored.accent
                && preset.config.canvas == stored.canvas
                && preset.config.glowA == stored.glowA
                && preset.config.glowB == stored.glowB
                && preset.config.glowC == stored.glowC
        }
    }

    var themeName: String { matchedPreset?.name ?? "自定义" }

    private init() {
        let loaded = ThemeStore.load() ?? .standard
        stored = loaded
        ThemeRuntime.config = loaded
        ThemeRuntime.palette = ThemePalette.resolve(loaded)
    }

    func apply(_ preset: ThemePreset) {
        config = preset.config
    }

    func reset() {
        config = .standard
    }

    // MARK: 取色器绑定

    var accentColor: Color {
        get { Color(hex: stored.accent) }
        set { config.accent = newValue.hexRGB }
    }

    var canvasColor: Color {
        get { Color(hex: stored.canvas) }
        set { config.canvas = newValue.hexRGB }
    }

    var glowColor: Color {
        get { Color(hex: stored.glowA) }
        set {
            // 光晕主色一变，另外两团跟着做近似色偏移，整体仍然协调
            config.glowA = newValue.hexRGB
            config.glowB = newValue.lightened(0.10).hexRGB
            config.glowC = newValue.darkened(0.10).hexRGB
        }
    }

    var glowStrength: Double {
        get { stored.glowStrength }
        set { config.glowStrength = max(0, min(1.6, newValue)) }
    }

    // MARK: 持久化

    private static func load() -> ThemeConfig? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ThemeConfig.self, from: data)
    }

    private static func save(_ config: ThemeConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
