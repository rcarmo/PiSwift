import SwiftUI

enum PiShellTheme {
    static let panelRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let bubbleRadius: CGFloat = 10
    static let spacing: CGFloat = 12

    static var panelFill: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var surface: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var elevated: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }

    static var composerFill: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var separator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }

    static var messageHover: Color {
        #if os(macOS)
        Color(nsColor: .controlAccentColor).opacity(0.08)
        #else
        Color.accentColor.opacity(0.08)
        #endif
    }
}

struct PiMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor.gradient)
            Text("π")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("Pi")
    }
}
