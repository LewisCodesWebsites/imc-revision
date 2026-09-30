import SwiftUI
import UIKit

private func dynamic(light: UInt32, dark: UInt32) -> Color {
    func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
}

extension Color {
    static let imcAccent = dynamic(light: 0x2A47C4, dark: 0x8FA3FF)
    static let imcRight = dynamic(light: 0x17794A, dark: 0x5FD39A)
    static let imcWrong = dynamic(light: 0xB3261E, dark: 0xFF8A80)
    static let imcSkip = dynamic(light: 0x8A6D0B, dark: 0xE7C65A)
    static let imcCard = Color(UIColor.secondarySystemGroupedBackground)
    static let imcBackground = Color(UIColor.systemGroupedBackground)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.imcCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// Copies to the clipboard and briefly shows "Copied".
struct CopyButton: View {
    let text: String
    var prominent = false
    @State private var copied = false

    var body: some View {
        let button = Button {
            UIPasteboard.general.string = text
            Haptics.success()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
        } label: {
            Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
}

struct CodeBox: View {
    let code: String
    var body: some View {
        Text(code)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.imcBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary))
    }
}
