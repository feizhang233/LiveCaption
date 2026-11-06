import SwiftUI

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
