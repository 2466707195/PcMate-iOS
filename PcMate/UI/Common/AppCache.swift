import Foundation

// MARK: - 软件缓存清理
//
// PcMate 自己产生的缓存有三块：
//   1. URLCache（网络请求缓存，Agent 证书固定时用得不多，但配对流程会有）
//   2. Library/Caches（系统给 App 的缓存目录）
//   3. tmp（临时目录，文件和打印过程的中间产物）
//
// 注意：**不动 Documents**。用户下载的文件放在 Documents 里，
// 清缓存不能把用户的文件删掉。

enum AppCache {

    struct Report: Equatable {
        var urlBytes: Int64 = 0
        var cachesBytes: Int64 = 0
        var tempBytes: Int64 = 0

        var totalBytes: Int64 { urlBytes + cachesBytes + tempBytes }

        /// 给界面用的分段说明。
        var detail: String {
            "网络 \(AppCache.text(urlBytes)) · 缓存 \(AppCache.text(cachesBytes)) · 临时 \(AppCache.text(tempBytes))"
        }
    }

    static func text(_ bytes: Int64) -> String {
        Fmt.bytes(bytes)
    }

    // MARK: 统计

    static func measure() -> Report {
        var report = Report()
        let cache = URLCache.shared
        report.urlBytes = Int64(cache.currentDiskUsage) + Int64(cache.currentMemoryUsage)
        report.cachesBytes = directorySize(cachesURL)
        report.tempBytes = directorySize(FileManager.default.temporaryDirectory)
        return report
    }

    // MARK: 清理

    /// 清掉全部缓存，返回释放的字节数。
    @discardableResult
    static func clear() -> Int64 {
        let before = measure().totalBytes

        URLCache.shared.removeAllCachedResponses()
        removeContents(of: cachesURL)
        removeContents(of: FileManager.default.temporaryDirectory)

        // caches / tmp 目录本身保留，只清内容；再量一次拿真实释放量。
        let after = measure().totalBytes
        return max(0, before - after)
    }

    // MARK: 内部

    private static var cachesURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private static func directorySize(_ url: URL?) -> Int64 {
        guard let url else { return 0 }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private static func removeContents(of url: URL?) {
        guard let url else { return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for item in items {
            try? fm.removeItem(at: item)
        }
    }
}
