import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()
    private let network = NetworkMonitor()
    private let processes = ProcessMonitor()

    private var statusItem: NSStatusItem?
    private var menuBarView: MenuBarView?
    private var panels: [DetailView] = []
    private var launchMenuItem: NSMenuItem?
    private var graphsMenuItem: NSMenuItem?
    private var timer: Timer?
    private var isMenuOpen = false

    private static let showGraphsKey = "showMenuBarGraphs"

    /// 選單列是否顯示迷你趨勢圖（預設關閉，選單列空間不足時才放得下）
    private var showGraphs: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showGraphsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showGraphsKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }
        LaunchAtLogin.prepare()

        sample()
        buildStatusItem()

        let timer = Timer(timeInterval: Config.sampleInterval, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        // .common：選單打開時也持續更新
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // 開機時其他 App 的圖示可能比較晚出現，等一下再檢查趨勢圖是否放得下
        if showGraphs {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.revertGraphsIfHidden(notify: false)
            }
        }
    }

    @objc private func tick() {
        sample()
        if isMenuOpen { processes.sample() }
        menuBarView?.needsDisplay = true
        panels.forEach { $0.needsDisplay = true }
    }

    private func sample() {
        cpu.update()
        memory.update()
        network.update()
    }

    private static let autosaveName = "MacStats.main"
    private static let positionKey = "NSStatusItem Preferred Position \(autosaveName)"

    private func buildStatusItem() {
        // 新建立的圖示預設排在最左邊，在有瀏海的 MacBook 上容易被擋住。
        // 第一次執行時改排到最右邊（緊鄰系統圖示）；之後用 ⌘ 拖曳調整，系統會覆寫這個值
        if UserDefaults.standard.object(forKey: Self.positionKey) == nil {
            UserDefaults.standard.set(0, forKey: Self.positionKey)
        }

        let view = MenuBarView(cpu: cpu, memory: memory, network: network, showGraphs: showGraphs)
        let item = NSStatusBar.system.statusItem(withLength: view.preferredWidth)
        item.autosaveName = Self.autosaveName
        item.isVisible = true

        if let button = item.button {
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                view.topAnchor.constraint(equalTo: button.topAnchor),
                view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }

        // 下拉面板：CPU、記憶體、網路三欄並排
        let cpuDetail = CPUDetailView(monitor: cpu, processes: processes)
        panels = [cpuDetail, MemoryDetailView(monitor: memory), NetworkDetailView(monitor: network)]
        processes.onUpdate = { [weak cpuDetail] in cpuDetail?.needsDisplay = true }

        let menu = NSMenu()
        menu.delegate = self

        let dashboardItem = NSMenuItem()
        dashboardItem.view = DashboardView(panels: panels)
        menu.addItem(dashboardItem)
        menu.addItem(.separator())

        let activity = NSMenuItem(title: "打開活動監視器…", action: #selector(openActivityMonitor), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)

        let graphs = NSMenuItem(title: "選單列顯示趨勢圖", action: #selector(toggleGraphs), keyEquivalent: "")
        graphs.target = self
        menu.addItem(graphs)
        graphsMenuItem = graphs

        let launch = NSMenuItem(title: "登入時自動啟動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        menu.addItem(launch)
        launchMenuItem = launch

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "結束 MacStats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        menuBarView = view
    }

    // MARK: - 選單動作

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        processes.reset()
        processes.sample()

        graphsMenuItem?.state = showGraphs ? .on : .off
        if let launch = launchMenuItem {
            launch.state = LaunchAtLogin.isEnabled ? .on : .off
            launch.isEnabled = LaunchAtLogin.isAvailable
            if !LaunchAtLogin.isAvailable {
                launch.title = "登入時自動啟動（需用 install.sh 安裝）"
            }
        }
        panels.forEach { $0.needsDisplay = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    /// 移除後重新建立，讓系統依偏好位置重新排列（只改寬度的話，加寬的部分可能被擠進瀏海）
    private func rebuildStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        menuBarView = nil
        panels = []
        buildStatusItem()
    }

    @objc private func toggleGraphs() {
        showGraphs.toggle()
        // 等選單完全收起來再重建，避免在選單動作中移除自己所屬的圖示
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildStatusItem()
            if self.showGraphs {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.revertGraphsIfHidden(notify: true)
                }
            }
        }
    }

    /// 開了趨勢圖後放不下（被瀏海擋住或被系統隱藏），就自動關掉並提示
    private func revertGraphsIfHidden(notify: Bool) {
        guard showGraphs, isStatusItemHidden() else { return }
        showGraphs = false
        rebuildStatusItem()
        guard notify else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "選單列空間不足"
        alert.informativeText = "開啟趨勢圖後 MacStats 會被瀏海擋住，已自動關閉趨勢圖。\n可以到「系統設定 → 選單列」隱藏其他用不到的圖示來騰出空間。"
        alert.runModal()
    }

    private func isStatusItemHidden() -> Bool {
        guard let window = statusItem?.button?.window else { return true }
        if !window.occlusionState.contains(.visible) { return true }
        // 有瀏海的螢幕：圖示左緣跑到瀏海右緣的左邊，就是被擋住了
        if let screen = window.screen, let notch = screen.auxiliaryTopRightArea {
            let isLocal = notch.maxX <= screen.frame.width + 1
            let x = isLocal ? window.frame.minX - screen.frame.minX : window.frame.minX
            if x < notch.minX { return true }
        }
        return false
    }

    /// 程式已在執行時又被「打開」一次（例如從「應用程式」資料夾或 Spotlight）：
    /// 恢復成精簡顯示並排回最右邊。選單列上的圖示被擋住、點不到時，可以用這招救回來。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showGraphs = false
        UserDefaults.standard.set(0, forKey: Self.positionKey)
        rebuildStatusItem()
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// 避免登入自動啟動後又手動開一次，造成選單列出現兩組
    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != me }
    }
}
