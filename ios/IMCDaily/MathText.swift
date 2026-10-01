import SwiftUI

// Renders the small maths markup the question engine produces:
//   <span class="fr"><span>num</span><span>den</span></span>   stacked fraction
//   <sup>…</sup>  power,  <i>…</i>  italic letter,  <b>…</b>  bold
// Everything else is plain text. Lines wrap between words.

indirect enum MathNode {
    case text(String, italic: Bool, bold: Bool)
    case sup([MathNode])
    case frac([MathNode], [MathNode])
}

enum MathParser {
    private final class Element {
        let name: String
        let cls: String
        var children: [Child] = []
        init(name: String, cls: String) { self.name = name; self.cls = cls }
    }
    private enum Child { case text(String), element(Element) }

    static func parse(_ markup: String) -> [MathNode] {
        let root = Element(name: "root", cls: "")
        var stack: [Element] = [root]
        var i = markup.startIndex
        var textStart = i

        func flushText(upTo end: String.Index) {
            if textStart < end {
                stack.last!.children.append(.text(String(markup[textStart..<end])))
            }
        }

        while i < markup.endIndex {
            if markup[i] == "<", let close = markup[i...].firstIndex(of: ">") {
                flushText(upTo: i)
                let inner = markup[markup.index(after: i)..<close]
                if inner.hasPrefix("/") {
                    if stack.count > 1 { stack.removeLast() }
                } else {
                    let parts = inner.split(separator: " ", maxSplits: 1)
                    let name = parts.first.map(String.init)?.lowercased() ?? ""
                    var cls = ""
                    if parts.count > 1, let r = parts[1].range(of: "class=\"") {
                        let rest = parts[1][r.upperBound...]
                        cls = String(rest.prefix { $0 != "\"" })
                    }
                    let el = Element(name: name, cls: cls)
                    stack.last!.children.append(.element(el))
                    if !["br", "img"].contains(name) { stack.append(el) }
                }
                i = markup.index(after: close)
                textStart = i
            } else {
                i = markup.index(after: i)
            }
        }
        flushText(upTo: markup.endIndex)
        return convert(root.children, italic: false, bold: false)
    }

    private static func convert(_ children: [Child], italic: Bool, bold: Bool) -> [MathNode] {
        var out: [MathNode] = []
        for child in children {
            switch child {
            case .text(let t):
                out.append(.text(decode(t), italic: italic, bold: bold))
            case .element(let el):
                switch el.name {
                case "span" where el.cls.contains("fr"):
                    let parts = el.children.compactMap { c -> Element? in
                        if case .element(let e) = c { return e } else { return nil }
                    }
                    if parts.count >= 2 {
                        out.append(.frac(convert(parts[0].children, italic: italic, bold: bold),
                                         convert(parts[1].children, italic: italic, bold: bold)))
                    }
                case "sup":
                    out.append(.sup(convert(el.children, italic: italic, bold: bold)))
                case "i", "em":
                    out += convert(el.children, italic: true, bold: bold)
                case "b", "strong":
                    out += convert(el.children, italic: italic, bold: true)
                default:
                    out += convert(el.children, italic: italic, bold: bold)
                }
            }
        }
        return out
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Plain-text version for VoiceOver.
    static func plain(_ nodes: [MathNode]) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let t, _, _): return t
            case .sup(let n): return " to the power " + plain(n) + " "
            case .frac(let a, let b): return " " + plain(a) + " over " + plain(b) + " "
            }
        }.joined()
    }
}

// MARK: - Building Text

private func mathFont(_ size: CGFloat, bold: Bool) -> Font {
    .system(size: size, weight: bold ? .semibold : .regular, design: .serif)
}

/// Joins nodes into one Text (used inside fractions, where nothing wraps).
private func inlineText(_ nodes: [MathNode], size: CGFloat) -> Text {
    var result = Text("")
    for node in nodes {
        switch node {
        case .text(let t, let italic, let bold):
            var piece = Text(t).font(mathFont(size, bold: bold))
            if italic { piece = piece.italic() }
            result = result + piece
        case .sup(let inner):
            result = result + Text("\u{2009}").font(mathFont(size, bold: false)) + inlineText(inner, size: size * 0.68).baselineOffset(size * 0.42)
        case .frac(let a, let b):
            result = result + inlineText(a, size: size) + Text("/").font(mathFont(size, bold: false)) + inlineText(b, size: size)
        }
    }
    return result
}

// MARK: - Tokens for the wrapping layout

private struct MathToken {
    enum Kind { case text(Text), frac(Text, Text) }
    let kind: Kind
    let spaceBefore: Bool
}

private func tokenize(_ nodes: [MathNode], size: CGFloat) -> [MathToken] {
    var tokens: [MathToken] = []
    var current: Text? = nil
    var pendingSpace = false      // was there whitespace before the token being built?
    var currentSpace = false

    func flush() {
        if let c = current { tokens.append(MathToken(kind: .text(c), spaceBefore: currentSpace)) }
        current = nil
    }
    func append(_ t: Text) {
        if current == nil { currentSpace = pendingSpace; pendingSpace = false; current = t }
        else { current = current! + t }
    }

    for node in nodes {
        switch node {
        case .text(let t, let italic, let bold):
            // Split on spaces so lines can wrap between words.
            var word = ""
            func emitWord() {
                guard !word.isEmpty else { return }
                var piece = Text(word).font(mathFont(size, bold: bold))
                if italic { piece = piece.italic() }
                append(piece)
                word = ""
            }
            for ch in t {
                if ch == " " || ch == "\n" || ch == "\u{00A0}" {
                    emitWord()
                    flush()
                    pendingSpace = true
                } else {
                    word.append(ch)
                }
            }
            emitWord()
        case .sup(let inner):
            append(Text("\u{2009}").font(mathFont(size, bold: false)) + inlineText(inner, size: size * 0.68).baselineOffset(size * 0.42))
        case .frac(let a, let b):
            flush()
            tokens.append(MathToken(kind: .frac(inlineText(a, size: size * 0.86), inlineText(b, size: size * 0.86)),
                                    spaceBefore: pendingSpace))
            pendingSpace = false
        }
    }
    flush()
    return tokens
}

// MARK: - Views

private struct SpaceBefore: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// Stacks numerator over denominator with a bar as wide as the wider of the two.
private struct FractionLayout: Layout {
    let size: CGFloat
    private var gap: CGFloat { size * 0.1 }
    private var bar: CGFloat { max(1, size * 0.055) }
    private var pad: CGFloat { size * 0.1 }

    private func measure(_ subviews: Subviews) -> (num: CGSize, den: CGSize, width: CGFloat) {
        let num = subviews[0].sizeThatFits(.unspecified)
        let den = subviews[1].sizeThatFits(.unspecified)
        return (num, den, max(num.width, den.width) + pad * 2)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = measure(subviews)
        return CGSize(width: m.width, height: m.num.height + gap + bar + gap + m.den.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = measure(subviews)
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(m.num))
        subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.minY + m.num.height + gap), anchor: .topLeading,
                          proposal: ProposedViewSize(width: m.width, height: bar))
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.minY + m.num.height + gap + bar + gap), anchor: .top,
                          proposal: ProposedViewSize(m.den))
    }

    // Put the text baseline a little below the bar, like printed maths.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        let m = measure(subviews)
        return bounds.minY + m.num.height + gap + bar / 2 + size * 0.3
    }
}

private struct FractionView: View {
    let num: Text
    let den: Text
    let size: CGFloat

    var body: some View {
        FractionLayout(size: size) {
            num.fixedSize()
            den.fixedSize()
            Rectangle()
        }
    }
}

/// A wrapping row of tokens, aligned on their text baselines.
private struct MathFlowLayout: Layout {
    var lineSpacing: CGFloat

    private struct Line { var items: [(index: Int, x: CGFloat)] = []; var ascent: CGFloat = 0; var descent: CGFloat = 0; var width: CGFloat = 0 }

    private func lines(for subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for (i, sv) in subviews.enumerated() {
            let d = sv.dimensions(in: .unspecified)
            let baseline = d[VerticalAlignment.firstTextBaseline]
            let gap = lines[lines.count - 1].items.isEmpty ? 0 : sv[SpaceBefore.self]
            if !lines[lines.count - 1].items.isEmpty && lines[lines.count - 1].width + gap + d.width > maxWidth {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            let x = line.items.isEmpty ? 0 : line.width + sv[SpaceBefore.self]
            line.items.append((i, x))
            line.width = x + d.width
            line.ascent = max(line.ascent, baseline)
            line.descent = max(line.descent, d.height - baseline)
            lines[lines.count - 1] = line
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let ls = lines(for: subviews, maxWidth: maxWidth)
        let height = ls.reduce(0) { $0 + $1.ascent + $1.descent } + lineSpacing * CGFloat(max(0, ls.count - 1))
        let width = ls.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, maxWidth: bounds.width) {
            for item in line.items {
                let sv = subviews[item.index]
                let d = sv.dimensions(in: .unspecified)
                let baseline = d[VerticalAlignment.firstTextBaseline]
                sv.place(at: CGPoint(x: bounds.minX + item.x, y: y + line.ascent - baseline),
                         proposal: ProposedViewSize(width: d.width, height: d.height))
            }
            y += line.ascent + line.descent + lineSpacing
        }
    }
}

struct MathText: View {
    let markup: String
    var size: CGFloat = 22

    init(_ markup: String, size: CGFloat = 22) {
        self.markup = markup
        self.size = size
    }

    var body: some View {
        let nodes = MathParser.parse(markup)
        let tokens = tokenize(nodes, size: size)
        MathFlowLayout(lineSpacing: size * 0.3) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Group {
                    switch token.kind {
                    case .text(let t): t.fixedSize()
                    case .frac(let a, let b): FractionView(num: a, den: b, size: size)
                    }
                }
                .layoutValue(key: SpaceBefore.self, value: token.spaceBefore ? size * 0.27 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MathParser.plain(nodes))
    }
}
