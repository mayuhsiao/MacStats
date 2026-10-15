import Foundation

enum Fmt {
    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    static func percent1(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    /// 網速：12.3 KB/s、1.20 MB/s
    static func rate(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb < 1000 {
            return String(format: kb < 10 ? "%.1f KB/s" : "%.0f KB/s", kb)
        }
        let mb = kb / 1024
        if mb < 1000 {
            return String(format: mb < 10 ? "%.2f MB/s" : "%.1f MB/s", mb)
        }
        return String(format: "%.2f GB/s", mb / 1024)
    }

    /// 精簡模式用，省略「/s」以節省選單列空間：12 KB、1.20 MB
    static func rateShort(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb < 1000 {
            return String(format: kb < 10 ? "%.1f KB" : "%.0f KB", kb)
        }
        let mb = kb / 1024
        if mb < 1000 {
            return String(format: mb < 10 ? "%.2f MB" : (mb < 100 ? "%.1f MB" : "%.0f MB"), mb)
        }
        return String(format: "%.2f GB", mb / 1024)
    }

    /// 容量：512 MB、8.25 GB
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = value
        var i = 0
        while v >= 1000 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return String(format: "%.0f B", v) }
        let pattern = v < 10 ? "%.2f %@" : (v < 100 ? "%.1f %@" : "%.0f %@")
        return String(format: pattern, v, units[i])
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    /// 開機時間：3 天 4 小時 12 分
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小時 \(minutes) 分" }
        if hours > 0 { return "\(hours) 小時 \(minutes) 分" }
        return "\(minutes) 分"
    }
}
