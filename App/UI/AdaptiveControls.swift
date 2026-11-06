import SwiftUI

/// Keeps the same controls and ordering when a row needs to become a column.
struct AdaptiveControls<Content: View>: View {
    var horizontalSpacing: CGFloat = 16
    var verticalSpacing: CGFloat = 12
    var verticalAlignment: VerticalAlignment = .center
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: verticalAlignment, spacing: horizontalSpacing) { content }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: verticalSpacing) { content }
        }
    }
}

enum CaptionLayout {
    static func contentPadding(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .compact ? 16 : 24
    }
}

struct CaptionPageContent<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(CaptionLayout.contentPadding(for: horizontalSizeClass))
                .frame(maxWidth: 1_100)
                .frame(maxWidth: .infinity)
        }
    }
}
