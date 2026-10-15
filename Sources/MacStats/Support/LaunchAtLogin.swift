import Foundation

/// 登入時自動啟動：在 ~/Library/LaunchAgents 放一個 LaunchAgent。
/// 沒有設定 KeepAlive，所以手動「結束」後不會被系統自動重開，方便修改程式。
enum LaunchAtLogin {
    static let label = "com.maxhsiao.MacStats"
    private static let configuredKey = "didConfigureLaunchAtLogin"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 只有打包成 .app 執行時才能設定（用 swift run 開發時不寫入，避免指向暫存的執行檔）
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 程式啟動時呼叫：第一次執行自動開啟；已開啟則更新執行檔路徑（例如 App 被搬移過）
    static func prepare() {
        guard isAvailable else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: configuredKey) {
            setEnabled(true)
            defaults.set(true, forKey: configuredKey)
        } else if isEnabled {
            setEnabled(true)
        }
    }

    static func setEnabled(_ enabled: Bool) {
        guard enabled else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }
        guard isAvailable, let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            // 內容沒變就不重寫，避免每次啟動都跳出「已加入背景項目」通知
            if let existing = try? Data(contentsOf: plistURL), existing == data { return }
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            NSLog("MacStats: 無法寫入 LaunchAgent：\(error)")
        }
    }
}
