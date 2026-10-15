import AppKit
import UniformTypeIdentifiers

struct TopProcess {
    let pid: pid_t
    let name: String
    let cpu: Double   // 以單一核心為 100%，與「活動監視器」相同（多核心程式可超過 100%）
    let icon: NSImage
}

/// 耗用 CPU 最多的程式。
/// 透過 /bin/ps（setuid root）讀取所有程式的累計 CPU 時間，才看得到 WindowServer 等系統程式，
/// 再比較前後兩次的差值算出即時使用率。只在 CPU 選單打開時取樣，平常不耗資源。
final class ProcessMonitor {
    static let count = 5

    private(set) var top: [TopProcess] = []
    var onUpdate: (() -> Void)?

    private struct Row {
        let pid: pid_t
        let pcpu: Double
        let time: Double
        let path: String
    }

    private let queue = DispatchQueue(label: "MacStats.ps", qos: .utility)
    // 以下兩個只在 queue 上存取
    private var previous: [pid_t: Double] = [:]
    private var previousTime: TimeInterval?

    private var isSampling = false
    private var iconCache: [String: NSImage] = [:]

    /// 選單重新打開時呼叫，避免拿很久以前的資料算差值
    func reset() {
        queue.async {
            self.previous = [:]
            self.previousTime = nil
        }
    }

    func sample() {
        guard !isSampling else { return }
        isSampling = true
        queue.async {
            let result = self.compute(self.runPS())
            DispatchQueue.main.async {
                self.isSampling = false
                self.top = result.map(self.decorate)
                self.onUpdate?()
            }
        }
    }

    // MARK: - 背景執行

    private func runPS() -> (rows: [Row], psPid: pid_t) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Ao", "pid=,pcpu=,time=,comm="]
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return ([], 0) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let text = String(decoding: data, as: UTF8.self)
        let rows = text.split(separator: "\n").compactMap(Self.parse)
        return (rows, task.processIdentifier)
    }

    private func compute(_ sample: (rows: [Row], psPid: pid_t)) -> [(pid: pid_t, cpu: Double, path: String)] {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = previousTime.map { now - $0 } ?? 0

        var entries: [(pid: pid_t, cpu: Double, path: String)] = []
        for row in sample.rows where row.pid != sample.psPid {
            var cpu = row.pcpu  // 第一次取樣沒有差值可算，先用 ps 的平均值
            if dt > 0.2, let old = previous[row.pid] {
                cpu = max(row.time - old, 0) / dt * 100
            }
            entries.append((row.pid, cpu, row.path))
        }
        previous = Dictionary(sample.rows.map { ($0.pid, $0.time) }, uniquingKeysWith: { a, _ in a })
        previousTime = now

        return Array(entries.sorted { $0.cpu > $1.cpu }.prefix(Self.count))
    }

    /// 解析一行：「  406  23.0   9:00.99 /System/.../WindowServer」
    private static func parse(_ line: Substring) -> Row? {
        var rest = line[...]
        func field() -> Substring? {
            rest = rest.drop(while: { $0 == " " })
            guard !rest.isEmpty else { return nil }
            let f = rest.prefix(while: { $0 != " " })
            rest = rest.dropFirst(f.count)
            return f
        }
        guard let pidField = field(), let pid = pid_t(pidField),
              let pcpuField = field(), let pcpu = Double(pcpuField),
              let timeField = field(), let time = parseTime(timeField) else { return nil }
        let path = String(rest.drop(while: { $0 == " " }))
        return Row(pid: pid, pcpu: pcpu, time: time, path: path)
    }

    /// CPU 時間格式：[[天-]時:]分:秒.百分秒
    private static func parseTime(_ s: Substring) -> Double? {
        var str = s
        var days = 0.0
        if let dash = str.firstIndex(of: "-") {
            days = Double(str[..<dash]) ?? 0
            str = str[str.index(after: dash)...]
        }
        var total = 0.0
        for part in str.split(separator: ":") {
            guard let v = Double(part) else { return nil }
            total = total * 60 + v
        }
        return total + days * 86400
    }

    // MARK: - 名稱與圖示（主執行緒）

    private func decorate(_ entry: (pid: pid_t, cpu: Double, path: String)) -> TopProcess {
        let app = NSRunningApplication(processIdentifier: entry.pid)
        let fileName = (entry.path as NSString).lastPathComponent
        let name = app?.localizedName ?? (fileName.isEmpty ? "PID \(entry.pid)" : fileName)
        return TopProcess(pid: entry.pid, name: name, cpu: entry.cpu, icon: app?.icon ?? icon(for: entry.path))
    }

    /// 程式在 .app 裡就用最外層 App 的圖示（例如 Chrome Helper 顯示 Chrome 的圖示），否則用一般執行檔圖示
    private func icon(for path: String) -> NSImage {
        var key = "generic"
        if let range = path.range(of: ".app/") {
            key = String(path[..<range.lowerBound]) + ".app"
        }
        if let cached = iconCache[key] { return cached }
        let image = key == "generic"
            ? NSWorkspace.shared.icon(for: .unixExecutable)
            : NSWorkspace.shared.icon(forFile: key)
        iconCache[key] = image
        return image
    }
}
