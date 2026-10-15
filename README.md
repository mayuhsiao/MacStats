# MacStats

類似 iStat Menus 的 macOS 選單列監控工具，顯示 **CPU、記憶體、網速**，並附帶歷史趨勢圖。

```
CPU  MEM  ↑ 2.0 KB
10%  56%  ↓ 1.20 MB
```

## 功能

選單列只佔一格（約 145 pt，放得進有瀏海的 MacBook Air）：CPU、MEM 並排，右邊是上下兩行的網速。
點一下會展開三欄並排的詳細面板：

| 欄位 | 內容 |
| --- | --- |
| CPU | 3 分鐘趨勢圖（藍＝使用者、紅＝系統）、使用者／系統／閒置、負載平均、核心數、開機時間、**耗用 CPU 前 5 名的程式** |
| 記憶體 | 3 分鐘趨勢圖（藍＝App、紫＝已壓縮、橘＝固定）、各類用量、交換空間、記憶體壓力 |
| 網路 | 3 分鐘趨勢圖（上＝上傳、下＝下載）、累計流量、網卡、IP、峰值 |

- **選單列迷你趨勢圖**：預設關閉，可在選單中勾選「選單列顯示趨勢圖」開啟（會變寬約 90 pt，選單列空間夠才建議開）
- **文字顏色**：一律白色（若切換到淺色模式會自動變黑色）；顏色只用在圖表、圖例圓點與網速箭頭（↑ 紅、↓ 藍）
- **前 5 名程式**：透過 `/bin/ps` 取得（看得到 WindowServer 等系統程式），只在選單打開時每秒取樣，百分比與活動監視器相同（單核心 = 100%）
- **登入時自動啟動**：第一次執行會自動開啟，可在選單中切換
- **結束程式**：點選單列上的 MacStats →「結束 MacStats」
- **重新啟動**：到「應用程式」資料夾（`~/Applications`）或用 Spotlight 打開 MacStats
- **選單列上的 MacStats 不見了？** 通常是被瀏海擋住。程式還在執行時再打開一次 MacStats，就會恢復成精簡顯示並排回最右邊；開啟趨勢圖後若放不下，也會自動關閉並提示
- 支援淺色／深色模式；按住 ⌘ 拖曳可以調整位置（第一次執行會自動排在最右邊，避免被瀏海擋住）

## 使用方式

```bash
./install.sh     # 編譯 → 結束舊版 → 安裝到 ~/Applications → 啟動
./build.sh       # 只編譯打包到 build/MacStats.app
./uninstall.sh   # 結束程式、移除自動啟動與 App
```

**修改程式的流程**：改完 `Sources/` 裡的程式碼後，執行 `./install.sh` 就會自動關掉舊版並啟動新版。

## 專案結構

```
Sources/MacStats/
├── main.swift                程式進入點
├── AppDelegate.swift         建立選單列項目、下拉選單、每秒更新
├── Monitors/
│   ├── CPUMonitor.swift      host_statistics（HOST_CPU_LOAD_INFO）
│   ├── MemoryMonitor.swift   host_statistics64（HOST_VM_INFO64），算法同活動監視器
│   ├── NetworkMonitor.swift  getifaddrs，只計算 en* 實體網卡
│   └── ProcessMonitor.swift  /bin/ps，耗用 CPU 前幾名的程式
├── Views/
│   ├── StatusViews.swift     選單列上的顯示（MenuBarView）
│   ├── DetailViews.swift     下拉面板（三欄並排的趨勢圖＋數據）
│   └── Chart.swift           繪圖工具與配色（Palette）
└── Support/
    ├── History.swift         歷史資料與設定（取樣間隔、保留長度）
    ├── Format.swift          數字格式化
    └── LaunchAtLogin.swift   ~/Library/LaunchAgents 自動啟動
```

常改的設定：

- 取樣頻率、歷史長度：`Support/History.swift` 的 `Config`
- 顏色：`Views/Chart.swift` 的 `Palette`
- 顯示幾名程式：`Monitors/ProcessMonitor.swift` 的 `count`

## 備註

- 不需要 Xcode，只要 Command Line Tools（`xcode-select --install`）。`build.sh` 直接用 `swiftc` 編譯，並自動挑選與編譯器版本相符的 SDK，
  所以即使 Command Line Tools 更新不完整（`swift build` 失敗、預設 SDK 與編譯器版本不符）也能編譯。
- 自動啟動是透過 `~/Library/LaunchAgents/com.maxhsiao.MacStats.plist`，沒有設定 KeepAlive，手動結束後不會被系統重開。
  macOS 可能會跳出「已加入背景項目」的通知，屬於正常現象，可在「系統設定 → 一般 → 登入項目」中管理。
