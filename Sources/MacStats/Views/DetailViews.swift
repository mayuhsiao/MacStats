import AppKit

private let titleFont = NSFont.systemFont(ofSize: 13, weight: .bold)
private let titleValueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
private let sectionFont = NSFont.systemFont(ofSize: 12, weight: .bold)
private let rowFont = NSFont.systemFont(ofSize: 12, weight: .medium)
private let rowValueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
private let captionFont = NSFont.systemFont(ofSize: 10, weight: .semibold)

/// 點選選單列元件後，下拉選單最上方的詳細資訊面板
class DetailView: NSView {
    /// 每欄寬度。macOS 會把下拉選單的寬度限制在螢幕寬度的 60% 左右，
    /// 超過時選單會被截斷、下方選項的文字也會被裁掉，所以三欄加起來要小於這個上限
    /// （1280 pt 寬的螢幕每欄約 247 pt，外接大螢幕最寬 300 pt）
    static var width: CGFloat {
        let screenWidth = NSScreen.main?.frame.width ?? 1280
        return min(300, max(220, floor((screenWidth * 0.6 - 24 - 2) / 3)))
    }
    let pad: CGFloat = 14
    let rowHeight: CGFloat = 20
    let chartHeight: CGFloat = 84

    override var isFlipped: Bool { true }

    init(rows: Int) {
        let height = 34 + chartHeight + 10 + CGFloat(rows) * rowHeight + 8
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
    }

    required init?(coder: NSCoder) { fatalError() }

    var chartRect: NSRect {
        NSRect(x: pad, y: 34, width: bounds.width - pad * 2, height: chartHeight)
    }

    func rowY(_ index: Int) -> CGFloat {
        chartRect.maxY + 10 + CGFloat(index) * rowHeight + rowHeight / 2
    }

    func drawTitle(_ title: String, value: String) {
        title.draw(font: titleFont, color: Palette.text, x: pad, centerY: 18)
        value.draw(font: titleValueFont, color: Palette.text, rightEdge: bounds.width - pad, centerY: 18)
    }

    func drawChartFrame() {
        Chart.background(chartRect, radius: 4)
        Chart.gridLines(chartRect, at: [0.25, 0.5, 0.75])
    }

    func drawCaption(_ text: String) {
        text.draw(font: captionFont, color: Palette.text, x: chartRect.minX + 5, centerY: chartRect.minY + 9)
    }

    func drawRow(_ index: Int, _ label: String, _ value: String, dot: NSColor? = nil) {
        let y = rowY(index)
        var x = pad
        if let dot {
            dot.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y - 4, width: 8, height: 8)).fill()
            x += 14
        }
        label.draw(font: rowFont, color: Palette.text, x: x, centerY: y)
        value.draw(font: rowValueFont, color: Palette.text, rightEdge: bounds.width - pad, centerY: y)
    }

    /// 區段標題，上方加一條分隔線
    func drawSection(_ index: Int, _ title: String) {
        let y = rowY(index)
        NSColor.separatorColor.setFill()
        NSRect(x: pad, y: y - rowHeight / 2 + 1, width: bounds.width - pad * 2, height: 1).fill()
        title.draw(font: sectionFont, color: Palette.text, x: pad, centerY: y + 2)
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }
}

/// 精簡模式的下拉面板：CPU、記憶體、網路三欄並排
final class DashboardView: NSView {
    let panels: [DetailView]

    override var isFlipped: Bool { true }

    init(panels: [DetailView]) {
        self.panels = panels
        let width = panels.map(\.frame.width).reduce(0, +) + CGFloat(max(panels.count - 1, 0))
        let height = panels.map(\.frame.height).max() ?? 0
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        var x: CGFloat = 0
        for panel in panels {
            panel.setFrameOrigin(NSPoint(x: x, y: 0))
            addSubview(panel)
            x += panel.frame.width + 1
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        for panel in panels.dropLast() {
            NSRect(x: panel.frame.maxX, y: 12, width: 1, height: bounds.height - 24).fill()
        }
    }
}

private let historyCaption = "最近 \(Config.historyLength / 60) 分鐘"

final class CPUDetailView: DetailView {
    let monitor: CPUMonitor
    let processes: ProcessMonitor
    private let processSection = 6

    init(monitor: CPUMonitor, processes: ProcessMonitor) {
        self.monitor = monitor
        self.processes = processes
        super.init(rows: 7 + ProcessMonitor.count)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let m = monitor
        drawTitle("CPU 使用率", value: Fmt.percent(m.total))

        drawChartFrame()
        Chart.stacked([m.systemHistory.values, m.userHistory.values],
                      colors: [Palette.system, Palette.user],
                      capacity: Config.historyLength, in: chartRect, radius: 4)
        drawCaption(historyCaption)

        drawRow(0, "使用者", Fmt.percent1(m.user), dot: Palette.user)
        drawRow(1, "系統", Fmt.percent1(m.system), dot: Palette.system)
        drawRow(2, "閒置", Fmt.percent1(m.idle), dot: .tertiaryLabelColor)
        drawRow(3, "負載平均", m.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
        drawRow(4, "核心數", "\(m.coreCount)")
        drawRow(5, "開機時間", Fmt.duration(m.uptime))

        drawSection(processSection, "耗用 CPU 最多的程式")
        if processes.top.isEmpty {
            "讀取中…".draw(font: rowFont, color: Palette.text, x: pad, centerY: rowY(processSection + 1))
        }
        for (i, p) in processes.top.enumerated() {
            drawProcess(processSection + 1 + i, p)
        }
    }

    private func drawProcess(_ index: Int, _ p: TopProcess) {
        let y = rowY(index)
        let iconSize: CGFloat = 16
        p.icon.draw(in: NSRect(x: pad, y: y - iconSize / 2, width: iconSize, height: iconSize),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        let value = String(format: "%.1f%%", p.cpu)
        let valueRight = bounds.width - pad
        value.draw(font: rowValueFont, color: Palette.text, rightEdge: valueRight, centerY: y)

        // 名稱太長時以「…」截斷，不壓到右邊的數字
        let nameX = pad + iconSize + 6
        let nameWidth = valueRight - 60 - nameX
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: Palette.text, .paragraphStyle: style]
        let h = p.name.size(font: rowFont).height
        (p.name as NSString).draw(in: NSRect(x: nameX, y: y - h / 2, width: nameWidth, height: h), withAttributes: attrs)
    }
}

final class MemoryDetailView: DetailView {
    let monitor: MemoryMonitor

    init(monitor: MemoryMonitor) {
        self.monitor = monitor
        super.init(rows: 7)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let m = monitor
        drawTitle("記憶體", value: Fmt.percent(m.usedFraction))

        drawChartFrame()
        Chart.stacked([m.wiredHistory.values, m.compressedHistory.values, m.appHistory.values],
                      colors: [Palette.memWired, Palette.memCompressed, Palette.memApp],
                      capacity: Config.historyLength, in: chartRect, radius: 4)
        drawCaption(historyCaption)

        let pressureText = [1: "正常", 2: "警告", 4: "嚴重"][m.pressureLevel] ?? "—"
        drawRow(0, "已使用", "\(Fmt.bytes(m.used)) / \(Fmt.bytes(m.total))")
        drawRow(1, "App 記憶體", Fmt.bytes(m.app), dot: Palette.memApp)
        drawRow(2, "固定記憶體", Fmt.bytes(m.wired), dot: Palette.memWired)
        drawRow(3, "已壓縮", Fmt.bytes(m.compressed), dot: Palette.memCompressed)
        drawRow(4, "快取檔案", Fmt.bytes(m.cached))
        drawRow(5, "交換空間", "\(Fmt.bytes(m.swapUsed)) / \(Fmt.bytes(m.swapTotal))")
        drawRow(6, "記憶體壓力", pressureText, dot: Palette.pressure(m.pressureLevel))
    }
}

final class NetworkDetailView: DetailView {
    let monitor: NetworkMonitor

    init(monitor: NetworkMonitor) {
        self.monitor = monitor
        super.init(rows: 6)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let m = monitor
        let iface = [m.interfaceName, m.primaryInterface.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        drawTitle("網路", value: iface.isEmpty ? "未連線" : iface)

        let scale = networkScale(m.uploadHistory, m.downloadHistory, lastN: Config.historyLength)
        drawChartFrame()
        Chart.mirrored(up: m.uploadHistory.values, down: m.downloadHistory.values,
                       upColor: Palette.upload, downColor: Palette.download,
                       scale: scale, capacity: Config.historyLength, in: chartRect, radius: 4)
        drawCaption("\(historyCaption)・刻度 \(Fmt.rate(scale))")

        drawRow(0, "上傳", Fmt.rate(m.uploadRate), dot: Palette.upload)
        drawRow(1, "下載", Fmt.rate(m.downloadRate), dot: Palette.download)
        drawRow(2, "本次累計上傳", Fmt.bytes(m.totalUploaded))
        drawRow(3, "本次累計下載", Fmt.bytes(m.totalDownloaded))
        drawRow(4, "IP 位址", m.ipAddress ?? "—")
        drawRow(5, "峰值", "↑ \(Fmt.rate(m.uploadHistory.peak(lastN: Config.historyLength)))  ↓ \(Fmt.rate(m.downloadHistory.peak(lastN: Config.historyLength)))")
    }
}
