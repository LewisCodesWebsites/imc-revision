import SwiftUI

// Diagrams sent by the question engine. Coordinates are maths-style (y goes up).
// Items are drawn in order, so later fills cover earlier ones ("bg" punches a hole).

struct Diagram: Codable, Hashable {
    let items: [DiagramItem]
}

struct DiagramItem: Codable, Hashable {
    let t: String                 // poly, circle, sector, line, label, dot, angle
    var pts: [[Double]]? = nil
    var c: [Double]? = nil
    var r: Double? = nil
    var a0: Double? = nil
    var a1: Double? = nil
    var a: [Double]? = nil
    var b: [Double]? = nil
    var at: [Double]? = nil
    var p1: [Double]? = nil
    var p2: [Double]? = nil
    var text: String? = nil
    var fill: String? = nil       // none, shade, soft, soft2, bg
    var dash: Bool? = nil
    var anchor: String? = nil
}

private struct Box {
    var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
    mutating func add(_ p: [Double]?) {
        guard let p, p.count >= 2 else { return }
        minX = min(minX, p[0]); maxX = max(maxX, p[0]); minY = min(minY, p[1]); maxY = max(maxY, p[1])
    }
    mutating func add(circle c: [Double]?, r: Double?) {
        guard let c, let r, c.count >= 2 else { return }
        add([c[0] - r, c[1] - r]); add([c[0] + r, c[1] + r])
    }
    var width: Double { max(maxX - minX, 0.001) }
    var height: Double { max(maxY - minY, 0.001) }
}

extension Diagram {
    fileprivate var bounds: Box {
        var box = Box()
        for item in items {
            item.pts?.forEach { box.add($0) }
            box.add(item.a); box.add(item.b); box.add(item.at)
            if item.t == "circle" || item.t == "sector" { box.add(circle: item.c, r: item.r) }
        }
        if !box.minX.isFinite { box = Box(minX: 0, minY: 0, maxX: 1, maxY: 1) }
        let pad = 0.14 * max(box.width, box.height)
        box.minX -= pad; box.minY -= pad; box.maxX += pad; box.maxY += pad
        return box
    }
}

struct DiagramView: View {
    let diagram: Diagram
    @Environment(\.colorScheme) private var scheme

    private var shade: Color { scheme == .dark ? Color(red: 0.55, green: 0.27, blue: 0.17) : Color(red: 0.96, green: 0.74, blue: 0.64) }

    private func fillColor(_ name: String?) -> Color? {
        switch name {
        case "shade": return shade
        case "soft": return Color.imcAccent.opacity(0.16)
        case "soft2": return Color.imcRight.opacity(0.16)
        case "bg": return Color.imcCard
        default: return nil
        }
    }

    var body: some View {
        let box = diagram.bounds
        Canvas { ctx, size in
            let k = min(size.width / box.width, size.height / box.height)
            let ox = (size.width - box.width * k) / 2
            let oy = (size.height - box.height * k) / 2
            func P(_ p: [Double]) -> CGPoint {
                CGPoint(x: ox + (p[0] - box.minX) * k, y: oy + (box.maxY - p[1]) * k)
            }
            let ink = Color.primary.opacity(0.85)
            let line = StrokeStyle(lineWidth: 1.6, lineJoin: .round)

            for item in diagram.items {
                switch item.t {
                case "poly":
                    guard let pts = item.pts, pts.count >= 2 else { continue }
                    var path = Path()
                    path.move(to: P(pts[0]))
                    pts.dropFirst().forEach { path.addLine(to: P($0)) }
                    path.closeSubpath()
                    if let f = fillColor(item.fill) { ctx.fill(path, with: .color(f)) }
                    ctx.stroke(path, with: .color(ink), style: line)

                case "circle":
                    guard let c = item.c, let r = item.r else { continue }
                    let centre = P(c), rr = r * k
                    let path = Path(ellipseIn: CGRect(x: centre.x - rr, y: centre.y - rr, width: 2 * rr, height: 2 * rr))
                    if let f = fillColor(item.fill) { ctx.fill(path, with: .color(f)) }
                    ctx.stroke(path, with: .color(ink), style: line)

                case "sector":
                    guard let c = item.c, let r = item.r, let a0 = item.a0, let a1 = item.a1 else { continue }
                    var path = Path()
                    path.move(to: P(c))
                    let steps = 48
                    for s in 0...steps {
                        let th = (a0 + (a1 - a0) * Double(s) / Double(steps)) * .pi / 180
                        path.addLine(to: P([c[0] + r * cos(th), c[1] + r * sin(th)]))
                    }
                    path.closeSubpath()
                    if let f = fillColor(item.fill) { ctx.fill(path, with: .color(f)) }
                    ctx.stroke(path, with: .color(ink), style: line)

                case "line":
                    guard let a = item.a, let b = item.b else { continue }
                    var path = Path()
                    path.move(to: P(a)); path.addLine(to: P(b))
                    let style = (item.dash ?? false)
                        ? StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [5, 4])
                        : line
                    ctx.stroke(path, with: .color(item.dash ?? false ? Color.secondary : ink), style: style)

                case "dot":
                    guard let at = item.at else { continue }
                    let p = P(at)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(ink))

                case "angle":
                    guard let at = item.at, let p1 = item.p1, let p2 = item.p2 else { continue }
                    let v = P(at), q1 = P(p1), q2 = P(p2)
                    let t1 = atan2(q1.y - v.y, q1.x - v.x)
                    var d = atan2(q2.y - v.y, q2.x - v.x) - t1
                    while d > .pi { d -= 2 * .pi }
                    while d <= -.pi { d += 2 * .pi }
                    let rad: CGFloat = 22
                    var arc = Path()
                    for s in 0...24 {
                        let th = t1 + d * Double(s) / 24
                        let pt = CGPoint(x: v.x + rad * cos(th), y: v.y + rad * sin(th))
                        if s == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
                    }
                    ctx.stroke(arc, with: .color(Color.imcAccent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    if let text = item.text {
                        let mid = t1 + d / 2
                        let at = CGPoint(x: v.x + 38 * cos(mid), y: v.y + 38 * sin(mid))
                        ctx.draw(Text(text).font(.system(size: 17, design: .serif)).italic()
                                    .foregroundColor(Color.imcAccent), at: at, anchor: .center)
                    }

                case "label":
                    guard let at = item.at, let text = item.text else { continue }
                    let isLetter = text.count == 1 && text.first?.isLetter == true
                    var label = Text(text).font(.system(size: 16, weight: .medium, design: .serif))
                    if isLetter { label = label.italic() }
                    let anchor: UnitPoint = item.anchor == "l" ? .leading : (item.anchor == "r" ? .trailing : .center)
                    ctx.draw(label.foregroundColor(.primary), at: P(at), anchor: anchor)

                default:
                    continue
                }
            }
        }
        .aspectRatio(box.width / box.height, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 260)
        .padding(12)
        .background(Color.imcCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Diagram")
    }
}
