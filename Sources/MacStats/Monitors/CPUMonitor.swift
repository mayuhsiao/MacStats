import Darwin
import Foundation

/// 讀取整體 CPU 使用率（所有核心合計），比較前後兩次的 tick 差值
final class CPUMonitor {
    private(set) var user: Double = 0      // 0...1，含 nice
    private(set) var system: Double = 0
    private(set) var idle: Double = 1
    var total: Double { user + system }

    private(set) var userHistory = History()
    private(set) var systemHistory = History()
    private(set) var loadAverage: [Double] = [0, 0, 0]

    let coreCount = ProcessInfo.processInfo.activeProcessorCount
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private let host = mach_host_self()
    private var previous: host_cpu_load_info?

    func update() {
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { loadAverage = loads }

        guard let info = readTicks() else { return }
        defer { previous = info }
        guard let prev = previous else { return }

        // cpu_ticks 順序：USER, SYSTEM, IDLE, NICE；用 &- 處理計數器溢位
        let u = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0) + Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let s = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let i = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let sum = u + s + i
        guard sum > 0 else { return }

        user = u / sum
        system = s / sum
        idle = i / sum
        userHistory.append(user)
        systemHistory.append(system)
    }

    private func readTicks() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
