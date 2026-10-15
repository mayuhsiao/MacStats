import AppKit

enum Palette {
    static let user = NSColor.systemBlue
    static let system = NSColor.systemRed
    static let upload = NSColor.systemRed
    static let download = NSColor.systemBlue
    static let memApp = NSColor.systemBlue
    static let memWired = NSColor.systemOrange
    static let memCompressed = NSColor.systemPurple

    /// 文字顏色：深色背景用純白；萬一選單列或選單是淺色，自動改成黑色以免看不到
    static let text = NSColor(name: "MacStatsText") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        return (dark == .darkAqua || dark == .vibrantDark) ? .white : .black
    }

    static func pressure(_ level: Int) -> NSColor {
        switch level {
        case 4: return .systemRed
        case 2: return .systemOrange
        default: return .systemGreen
        }
    }
}

/// 歷史趨勢圖的繪圖工具。資料以 0...1 的比例表示（0 = 圖表底部），
/// 最新一筆畫在最右邊。同時支援 flipped 與一般座標系。
enum Chart {
    private static var isFlipped: Bool {
        NSGraphicsContext.current?.isFlipped ?? false
    }

    private static func point(_ x: CGFloat, _ fraction: Double, in rect: NSRect) -> NSPoint {
        let f = CGFloat(min(max(fraction, 0), 1))
        let y = isFlipped ? rect.maxY - f * rect.height : rect.minY + f * rect.height
        return NSPoint(x: x, y: y)
    }

    static func background(_ rect: NSRect, radius: CGFloat) {
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    static func gridLines(_ rect: NSRect, at fractions: [Double]) {
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        for f in fractions {
            let path = NSBezierPath()
            path.lineWidth = 0.5
            path.move(to: point(rect.minX, f, in: rect))
            path.line(to: point(rect.maxX, f, in: rect))
            path.stroke()
        }
    }

    /// 在 lower 與 upper 之間填滿階梯狀的區域
    static func band(lower: [Double], upper: [Double], color: NSColor, capacity: Int, in rect: NSRect) {
        let n = min(lower.count, upper.count, capacity)
        guard n > 0 else { return }
        let w = rect.width / CGFloat(capacity)
        let lo = Array(lower.suffix(n))
        let hi = Array(upper.suffix(n))

        let path = NSBezierPath()
        for i in 0..<n {
            let x = rect.maxX - CGFloat(n - i) * w
            let p = point(x, hi[i], in: rect)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
            path.line(to: point(x + w, hi[i], in: rect))
        }
        for i in (0..<n).reversed() {
            let x = rect.maxX - CGFloat(n - i) * w
            path.line(to: point(x + w, lo[i], in: rect))
            path.line(to: point(x, lo[i], in: rect))
        }
        path.close()
        color.setFill()
        path.fill()
    }

    /// 堆疊面積圖：series[0] 在最下面
    static func stacked(_ series: [[Double]], colors: [NSColor], capacity: Int, in rect: NSRect, radius: CGFloat = 0) {
        withClip(rect, radius: radius) {
            let n = series.map(\.count).min() ?? 0
            var lower = [Double](repeating: 0, count: n)
            for (values, color) in zip(series, colors) {
                let upper = zip(lower, values.suffix(n)).map { $0 + $1 }
                band(lower: lower, upper: upper, color: color, capacity: capacity, in: rect)
                lower = upper
            }
        }
    }

    /// 上下鏡像圖：上半部是上傳，下半部是下載（同 iStat Menus）
    static func mirrored(up: [Double], down: [Double], upColor: NSColor, downColor: NSColor,
                         scale: Double, capacity: Int, in rect: NSRect, radius: CGFloat = 0) {
        withClip(rect, radius: radius) {
            let s = max(scale, 1)
            let mid = [Double](repeating: 0.5, count: up.count)
            band(lower: mid, upper: up.map { 0.5 + 0.5 * $0 / s }, color: upColor, capacity: capacity, in: rect)
            let midDown = [Double](repeating: 0.5, count: down.count)
            band(lower: down.map { 0.5 - 0.5 * $0 / s }, upper: midDown, color: downColor, capacity: capacity, in: rect)
        }
    }

    private static func withClip(_ rect: NSRect, radius: CGFloat, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// 網速圖表的刻度：取視窗內最大值，至少 10 KB/s，避免雜訊被放大
func networkScale(_ histories: History..., lastN n: Int) -> Double {
    max(histories.map { $0.peak(lastN: n) }.max() ?? 0, 10 * 1024)
}

extension String {
    func size(font: NSFont) -> NSSize {
        (self as NSString).size(withAttributes: [.font: font])
    }

    /// 以 centerY 垂直置中繪製文字；若給 rightEdge 則靠右對齊
    func draw(font: NSFont, color: NSColor, x: CGFloat = 0, rightEdge: CGFloat? = nil, centerY: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (self as NSString).size(withAttributes: attrs)
        let originX = rightEdge.map { $0 - size.width } ?? x
        (self as NSString).draw(at: NSPoint(x: originX, y: centerY - size.height / 2), withAttributes: attrs)
    }
}
