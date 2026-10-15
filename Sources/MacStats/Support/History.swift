import Foundation

enum Config {
    /// 每秒取樣一次，保留 180 筆 = 最近 3 分鐘
    static let sampleInterval: TimeInterval = 1
    static let historyLength = 180
    /// 選單列迷你圖的寬度（pt），每 1pt 畫一筆資料
    static let miniGraphWidth: CGFloat = 26
}

/// 固定長度的歷史紀錄，超過容量時丟掉最舊的資料
struct History {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int = Config.historyLength) {
        self.capacity = capacity
    }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    var last: Double { values.last ?? 0 }

    func peak(lastN n: Int) -> Double {
        values.suffix(n).max() ?? 0
    }
}
