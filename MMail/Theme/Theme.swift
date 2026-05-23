import SwiftUI

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

// MARK: - Palette (light + dark token sets ported from tokens.css / styles.css)

struct Palette {
    // Brand
    let brandBlue: Color
    let brandBlue600: Color
    let brandBlue700: Color
    let brandBlue100: Color
    let brandBlue50: Color
    let magenta: Color
    let magenta600: Color
    let magenta100: Color

    // Neutral text
    let fg1: Color
    let fg2: Color
    let fg3: Color
    let fg4: Color

    // Surfaces
    let bg1: Color
    let bg2: Color
    let bg3: Color
    let bg4: Color

    // Lines
    let border: Color
    let borderStrong: Color

    // Semantic
    let success: Color
    let success100: Color
    let warning: Color
    let warning100: Color
    let danger: Color
    let danger100: Color

    // For folder-active text in dark mode
    let activeFolderText: Color

    let isDark: Bool

    static let light = Palette(
        brandBlue: Color(hex: "2D3DEC"),
        brandBlue600: Color(hex: "2536D1"),
        brandBlue700: Color(hex: "1E2DB0"),
        brandBlue100: Color(hex: "EEF1FF"),
        brandBlue50: Color(hex: "F5F7FF"),
        magenta: Color(hex: "E91E78"),
        magenta600: Color(hex: "C9156A"),
        magenta100: Color(hex: "FFF1F7"),
        fg1: Color(hex: "0E0F1A"),
        fg2: Color(hex: "3F4357"),
        fg3: Color(hex: "6B7088"),
        fg4: Color(hex: "9AA0B4"),
        bg1: Color(hex: "FFFFFF"),
        bg2: Color(hex: "F8F9FC"),
        bg3: Color(hex: "F1F3F9"),
        bg4: Color(hex: "E6E9F2"),
        border: .rgba(14, 15, 26, 0.08),
        borderStrong: .rgba(14, 15, 26, 0.14),
        success: Color(hex: "1FB36B"),
        success100: Color(hex: "E5F7EE"),
        warning: Color(hex: "F4A52A"),
        warning100: Color(hex: "FFF6E5"),
        danger: Color(hex: "E5484D"),
        danger100: Color(hex: "FCEBEC"),
        activeFolderText: Color(hex: "2D3DEC"),
        isDark: false
    )

    static let dark = Palette(
        brandBlue: Color(hex: "2D3DEC"),
        brandBlue600: Color(hex: "2536D1"),
        brandBlue700: Color(hex: "1E2DB0"),
        brandBlue100: Color(hex: "20254A"),
        brandBlue50: Color(hex: "1B1E3A"),
        magenta: Color(hex: "E91E78"),
        magenta600: Color(hex: "C9156A"),
        magenta100: .rgba(233, 30, 120, 0.16),
        fg1: Color(hex: "F3F4F8"),
        fg2: Color(hex: "BFC2CF"),
        fg3: Color(hex: "8E92A4"),
        fg4: Color(hex: "5F6377"),
        bg1: Color(hex: "15161D"),
        bg2: Color(hex: "0F1015"),
        bg3: Color(hex: "1D1F28"),
        bg4: Color(hex: "292B36"),
        border: .rgba(255, 255, 255, 0.08),
        borderStrong: .rgba(255, 255, 255, 0.14),
        success: Color(hex: "1FB36B"),
        success100: .rgba(31, 179, 107, 0.16),
        warning: Color(hex: "F4A52A"),
        warning100: .rgba(244, 165, 42, 0.16),
        danger: Color(hex: "E5484D"),
        danger100: .rgba(229, 72, 77, 0.16),
        activeFolderText: Color(hex: "C5CCFF"),
        isDark: true
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Typography scale (native SF Pro; design used Plus Jakarta Sans)

enum Typo {
    static func display() -> Font { .system(size: 64, weight: .heavy) }
    static func h1() -> Font { .system(size: 48, weight: .heavy) }
    static func h2() -> Font { .system(size: 36, weight: .bold) }
    static func h3() -> Font { .system(size: 30, weight: .bold) }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}
