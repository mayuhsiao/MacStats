import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 不在 Dock 顯示圖示，只出現在選單列
    app.setActivationPolicy(.accessory)
    app.run()
}
