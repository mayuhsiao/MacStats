import Darwin
import Foundation

/// 記憶體用量，計算方式與「活動監視器」相同：
/// 已使用 = App 記憶體 + 固定記憶體 + 已壓縮
final class MemoryMonitor {
    let total = Double(ProcessInfo.processInfo.physicalMemory)

    private(set) var app: Double = 0
    private(set) var wired: Double = 0
    private(set) var compressed: Double = 0
    private(set) var cached: Double = 0
    private(set) var swapUsed: Double = 0
    private(set) var swapTotal: Double = 0
    /// 記憶體壓力：1 = 正常、2 = 警告、4 = 嚴重
    private(set) var pressureLevel: Int = 1

    var used: Double { app + wired + compressed }
    var usedFraction: Double { total > 0 ? min(used / total, 1) : 0 }

    // 各項佔總記憶體的比例，用來畫堆疊圖
    private(set) var appHistory = History()
    private(set) var wiredHistory = History()
    private(set) var compressedHistory = History()

    private let host = mach_host_self()
    private let pageSize: Double = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return Double(size)
    }()

    func update() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let anonymous = Double(stats.internal_page_count)
        let purgeable = Double(stats.purgeable_count)
        app = max(anonymous - purgeable, 0) * pageSize
        wired = Double(stats.wire_count) * pageSize
        compressed = Double(stats.compressor_page_count) * pageSize
        cached = (Double(stats.external_page_count) + purgeable) * pageSize

        appHistory.append(app / total)
        wiredHistory.append(wired / total)
        compressedHistory.append(compressed / total)

        readSwap()
        readPressure()
    }

    private func readSwap() {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = Double(swap.xsu_used)
            swapTotal = Double(swap.xsu_total)
        }
    }

    private func readPressure() {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            pressureLevel = Int(level)
        }
    }
}
