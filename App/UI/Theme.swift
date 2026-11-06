import Observation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "跟隨系統", light = "淺色", dark = "深色"
    var id: String { rawValue }
    var scheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}
enum CaptionBackground: String, CaseIterable, Identifiable {
    case solid = "純色", glass = "液態玻璃", transparent = "透明"
    var id: String { rawValue }
}
enum CaptionInk: String, CaseIterable, Identifiable {
    case white = "白色", yellow = "淡黃色", cyan = "淺青色"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .white: .white
        case .yellow: Color(red: 1, green: 0.93, blue: 0.57)
        case .cyan: Color(red: 0.66, green: 0.94, blue: 1)
        }
    }
}
enum CaptionTypeface: String, CaseIterable, Identifiable {
    case standard = "系統", rounded = "圓體", serif = "襯線", monospaced = "等寬"
    var id: String { rawValue }
    var design: Font.Design {
        switch self { case .standard: .default; case .rounded: .rounded; case .serif: .serif; case .monospaced: .monospaced }
    }
}

@MainActor @Observable
final class AppPreferences {
    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "captionFontSize") } }
    var lineCount: Int { didSet { defaults.set(lineCount, forKey: "captionLines") } }
    var ink: CaptionInk { didSet { defaults.set(ink.rawValue, forKey: "captionInk") } }
    var typeface: CaptionTypeface { didSet { defaults.set(typeface.rawValue, forKey: "captionTypeface") } }
    var background: CaptionBackground { didSet { defaults.set(background.rawValue, forKey: "captionBackground") } }
    var opacity: Double { didSet { defaults.set(opacity, forKey: "captionOpacity") } }
    @ObservationIgnored private let defaults = UserDefaults.standard
    init() {
        let d = UserDefaults.standard
        theme = AppTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        fontSize = d.object(forKey: "captionFontSize") == nil ? 32 : min(64, max(18, d.double(forKey: "captionFontSize")))
        lineCount = d.object(forKey: "captionLines") == nil ? 3 : min(8, max(1, d.integer(forKey: "captionLines")))
        ink = CaptionInk(rawValue: d.string(forKey: "captionInk") ?? "") ?? .white
        typeface = CaptionTypeface(rawValue: d.string(forKey: "captionTypeface") ?? "") ?? .standard
        background = CaptionBackground(rawValue: d.string(forKey: "captionBackground") ?? "") ?? .solid
        opacity = d.object(forKey: "captionOpacity") == nil ? 0.94 : min(1, max(0, d.double(forKey: "captionOpacity")))
    }
}

enum CaptionTheme {
    static let accent = Color(red: 0.153, green: 0.42, blue: 0.60)
    static let reading = Color(red: 0.063, green: 0.098, blue: 0.137)
    static let secondaryText = Color(red: 0.663, green: 0.741, blue: 0.792)
}

struct GlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(.background, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.25)))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}

func timecode(_ seconds: Double) -> String {
    let value = Int(max(0, seconds.isFinite ? seconds : 0))
    if value >= 3_600 { return String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60) }
    return String(format: "%02d:%02d", value / 60, value % 60)
}
