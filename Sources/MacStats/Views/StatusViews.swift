import AppKit

private let labelFont = NSFont.systemFont(ofSize: 9, weight: .bold)
private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
private let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
private let padding: CGFloat = 3
private let graphHeight: CGFloat = 16

/// 選單列上的顯示，CPU、記憶體、網速合併成一格（CPU 與 MEM 並排，標籤在上、數值在下）：
///   CPU  MEM  ↑ 2.0 KB
///    7%  60%  ↓ 1.20 MB
/// showGraphs 開啟時，在各項前加上迷你趨勢圖（較寬，選單列空間夠才建議開）。
/// 畫在 NSStatusItem 的按鈕上，點擊交給按鈕處理（彈出選單）。
final class MenuBarView: NSView {
    let cpu: CPUMonitor
    let memory: MemoryMonitor
    let network: NetworkMonitor
    var showGraphs: Bool

    private let blockWidth = max("100%".size(font: valueFont).width, "MEM".size(font: labelFont).width)
    private let arrowWidth = "↑".size(font: rateFont).width
    private let rateWidth = "8.88 MB".size(font: rateFont).width
    private let gap: CGFloat = 6

    init(cpu: CPUMonitor, memory: MemoryMonitor, network: NetworkMonitor, showGraphs: Bool) {
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.showGraphs = showGraphs
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var graphSlot: CGFloat { showGraphs ? Config.miniGraphWidth + 3 : 0 }

    var preferredWidth: CGFloat {
        padding + (graphSlot + blockWidth) * 2 + gap * 2 + graphSlot + arrowWidth + 3 + rateWidth + padding
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        var x = padding

        x = drawPercent("CPU", cpu.total, at: x, midY: midY) {
            Chart.stacked([self.cpu.systemHistory.values, self.cpu.userHistory.values],
                          colors: [Palette.system, Palette.user],
                          capacity: Int(Config.miniGraphWidth), in: $0, radius: 2)
        }
        x += gap
        x = drawPercent("MEM", memory.usedFraction, at: x, midY: midY) {
            Chart.stacked([self.memory.wiredHistory.values, self.memory.compressedHistory.values, self.memory.appHistory.values],
                          colors: [Palette.memWired, Palette.memCompressed, Palette.memApp],
                          capacity: Int(Config.miniGraphWidth), in: $0, radius: 2)
        }
        x += gap

        if showGraphs {
            let capacity = Int(Config.miniGraphWidth)
            let graph = graphRect(x: x, midY: midY)
            Chart.background(graph, radius: 2)
            Chart.mirrored(up: network.uploadHistory.values, down: network.downloadHistory.values,
                           upColor: Palette.upload, downColor: Palette.download,
                           scale: networkScale(network.uploadHistory, network.downloadHistory, lastN: capacity),
                           capacity: capacity, in: graph, radius: 2)
            x += graphSlot
        }

        // 網速上下兩行：箭頭保留紅/藍作為辨識，數字白色
        let top = midY + 5.5
        let bottom = midY - 5.5
        "↑".draw(font: rateFont, color: Palette.upload, x: x, centerY: top)
        "↓".draw(font: rateFont, color: Palette.download, x: x, centerY: bottom)
        x += arrowWidth + 3
        Fmt.rateShort(network.uploadRate).draw(font: rateFont, color: Palette.text, rightEdge: x + rateWidth, centerY: top)
        Fmt.rateShort(network.downloadRate).draw(font: rateFont, color: Palette.text, rightEdge: x + rateWidth, centerY: bottom)
    }

    /// 畫「(迷你圖) 標籤在上、百分比在下」，兩者置中對齊，回傳結束的 x
    private func drawPercent(_ label: String, _ fraction: Double, at startX: CGFloat, midY: CGFloat,
                             graph: (NSRect) -> Void) -> CGFloat {
        var x = startX
        if showGraphs {
            let rect = graphRect(x: x, midY: midY)
            Chart.background(rect, radius: 2)
            graph(rect)
            x += graphSlot
        }
        let center = x + blockWidth / 2
        let value = Fmt.percent(fraction)
        label.draw(font: labelFont, color: Palette.text, x: center - label.size(font: labelFont).width / 2, centerY: midY + 6)
        value.draw(font: valueFont, color: Palette.text, x: center - value.size(font: valueFont).width / 2, centerY: midY - 4)
        return x + blockWidth
    }

    private func graphRect(x: CGFloat, midY: CGFloat) -> NSRect {
        NSRect(x: x, y: midY - graphHeight / 2, width: Config.miniGraphWidth, height: graphHeight)
    }
}
