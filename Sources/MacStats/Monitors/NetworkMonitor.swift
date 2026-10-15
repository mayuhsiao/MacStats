import Darwin
import Foundation
import SystemConfiguration

/// 網路上傳/下載速度。只計算實體網卡（en0、en1…），
/// 避免 VPN（utun）等虛擬介面把同一筆流量重複計算。
final class NetworkMonitor {
    private(set) var uploadRate: Double = 0     // bytes/s
    private(set) var downloadRate: Double = 0
    private(set) var totalUploaded: Double = 0  // 本程式啟動後累計
    private(set) var totalDownloaded: Double = 0

    private(set) var uploadHistory = History()
    private(set) var downloadHistory = History()

    private(set) var primaryInterface: String?
    private(set) var interfaceName: String?     // 例如 Wi-Fi、乙太網路
    private(set) var ipAddress: String?

    private var lastIn: [String: UInt32] = [:]
    private var lastOut: [String: UInt32] = [:]
    private var lastTime: TimeInterval?

    private let store = SCDynamicStoreCreate(nil, "MacStats" as CFString, nil, nil)
    private var displayNames: [String: String] = [:]

    init() {
        loadDisplayNames()
    }

    func update() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var inBytes: [String: UInt32] = [:]
        var outBytes: [String: UInt32] = [:]
        var ipv4: [String: String] = [:]

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr else { continue }
            let name = String(cString: ifa.ifa_name)
            let family = addr.pointee.sa_family

            if family == sa_family_t(AF_LINK) {
                guard name.hasPrefix("en"), let data = ifa.ifa_data else { continue }
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                inBytes[name] = stats.ifi_ibytes
                outBytes[name] = stats.ifi_obytes
            } else if family == sa_family_t(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    ipv4[name] = String(cString: host)
                }
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let lastTime {
            let dt = max(now - lastTime, 0.001)
            // 計數器是 32 位元，用 &- 處理超過 4GB 後歸零的情況
            var dIn: Double = 0
            var dOut: Double = 0
            for (name, value) in inBytes {
                if let old = lastIn[name] { dIn += Double(value &- old) }
            }
            for (name, value) in outBytes {
                if let old = lastOut[name] { dOut += Double(value &- old) }
            }
            downloadRate = dIn / dt
            uploadRate = dOut / dt
            totalDownloaded += dIn
            totalUploaded += dOut
            downloadHistory.append(downloadRate)
            uploadHistory.append(uploadRate)
        }
        lastIn = inBytes
        lastOut = outBytes
        lastTime = now

        updatePrimaryInterface(ipv4: ipv4)
    }

    private func updatePrimaryInterface(ipv4: [String: String]) {
        var primary: String?
        if let store,
           let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? NSDictionary {
            primary = dict["PrimaryInterface"] as? String
        }
        if primary != primaryInterface, let primary, displayNames[primary] == nil {
            loadDisplayNames()  // 插上新網卡時重新抓名稱
        }
        primaryInterface = primary
        interfaceName = primary.flatMap { displayNames[$0] }
        ipAddress = primary.flatMap { ipv4[$0] }
    }

    private func loadDisplayNames() {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return }
        for iface in all {
            if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
               let display = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                displayNames[bsd] = display
            }
        }
    }
}
