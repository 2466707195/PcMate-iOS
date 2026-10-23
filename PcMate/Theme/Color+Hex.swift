import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {

    /// 以 0xRRGGBB 形式构造颜色（等价 Android 的 0xFFxxxxxx 去掉 alpha 位）
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// 与**卡片底色**按比例混合，得到**不透明**的浅色底。
    ///
    /// Aurora UI 硬规则：需要浅色底一律用这个，不要用 `color.opacity(0.1)` 铺面，
    /// 否则半透明底会把底层阴影透出来，看起来像垫了一块灰方块。
    ///
    /// 混的是 `Aurora.surface` 而不是纯白：浅色主题下就是白色（和以前一样），
    /// 深色主题下会混成深色，图标块、状态胶囊才不会变成一块白斑。
    func tint(_ strength: Double) -> Color {
        mixed(with: Aurora.surface, 1 - max(0, min(1, strength)))
    }

    /// 取出 0xRRGGBB（丢掉 alpha），用于把取色器的结果存进配置。
    var hexRGB: UInt32 {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0x000000 }
        let ri = UInt32(max(0, min(255, round(r * 255))))
        let gi = UInt32(max(0, min(255, round(g * 255))))
        let bi = UInt32(max(0, min(255, round(b * 255))))
        return (ri << 16) | (gi << 8) | bi
        #else
        return 0x000000
        #endif
    }

    /// 与另一种颜色按比例混合（amount = 0 返回自己，1 返回 other），结果**不透明**。
    func mixed(with other: Color, _ amount: Double) -> Color {
        let s = max(0, min(1, amount))
        #if canImport(UIKit)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        if UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
           UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2) {
            return Color(
                .sRGB,
                red: Double(r1) * (1 - s) + Double(r2) * s,
                green: Double(g1) * (1 - s) + Double(g2) * s,
                blue: Double(b1) * (1 - s) + Double(b2) * s,
                opacity: 1
            )
        }
        #endif
        return amount >= 0.5 ? other : self
    }

    /// 提亮（朝白色混）
    func lightened(_ amount: Double) -> Color { mixed(with: .white, amount) }

    /// 压暗（朝黑色混）
    func darkened(_ amount: Double) -> Color { mixed(with: .black, amount) }

    /// 感知亮度 0…1，用来判断底色是浅还是深。
    var perceivedLuminance: Double {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 1 }
        return 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        #else
        return 1
        #endif
    }

    /// 十六进制字符串形式的 ARGB（Android 侧对齐用）
    var argbHex: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "00000000" }
        return String(
            format: "%02X%02X%02X%02X",
            Int(round(a * 255)), Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255))
        )
        #else
        return "00000000"
        #endif
    }
}
