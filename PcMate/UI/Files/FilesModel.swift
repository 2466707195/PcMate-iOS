import Foundation
import SwiftUI

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct Breadcrumb: Identifiable {
    let title: String
    let path: String
    var id: String { path + "|" + title }
}

@MainActor
final class FilesModel: ObservableObject {

    let session: SessionController

    @Published private(set) var listing: RemoteListing?
    @Published private(set) var currentPath = ""
    @Published private(set) var loading = false
    @Published private(set) var uploading = false
    @Published private(set) var downloadingPath: String?
    @Published var search = ""
    @Published var errorMessage: String?
    @Published var actionMessage: String?
    @Published var exportItem: ExportItem?

    init(session: SessionController) {
        self.session = session
    }

    var entries: [RemoteFileEntry] {
        guard let listing else { return [] }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? listing.entries : listing.entries.filter {
            $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isDir != rhs.isDir { return lhs.isDir }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var isWindows: Bool { session.hostInfo?.os == .windows }

    var canGoUp: Bool {
        !currentPath.isEmpty && currentPath != "/"
    }

    var canWrite: Bool {
        !currentPath.isEmpty && currentPath != "/"
    }

    var parentPath: String {
        if currentPath.isEmpty { return "" }
        if currentPath == "/" { return "" }
        if isDriveRoot(currentPath) { return "" }
        return RemotePath.parent(currentPath)
    }

    var breadcrumbs: [Breadcrumb] {
        if currentPath.isEmpty {
            return [Breadcrumb(title: "此电脑", path: "")]
        }
        if currentPath == "/" {
            return [Breadcrumb(title: "根目录", path: "/")]
        }
        let normalized = currentPath.replacingOccurrences(of: "\\", with: "/")
        let comps = normalized.split(separator: "/").map(String.init)
        var result: [Breadcrumb] = []
        if isWindows {
            result.append(Breadcrumb(title: "此电脑", path: ""))
        } else {
            result.append(Breadcrumb(title: "根目录", path: "/"))
        }
        var accumulated = isWindows ? "" : "/"
        for (index, comp) in comps.enumerated() {
            if isWindows && index == 0 {
                accumulated = comp + "/"
            } else if accumulated.hasSuffix("/") {
                accumulated += comp
            } else {
                accumulated += "/" + comp
            }
            result.append(Breadcrumb(title: comp, path: accumulated))
        }
        return result
    }

    func load(path: String? = nil) async {
        guard !loading else { return }
        let target: String
        if let path {
            target = path
        } else if currentPath.isEmpty && session.activeTransport == .ssh {
            target = session.initialPath
        } else {
            target = currentPath
        }

        loading = true
        errorMessage = nil
        do {
            let result = try await session.list(path: target)
            listing = result
            currentPath = result.path
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func goUp() async {
        guard canGoUp else { return }
        await load(path: parentPath)
    }

    func makeDirectory(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "文件夹名称不能为空。"
            return
        }
        guard !trimmed.contains("/"), !trimmed.contains("\\") else {
            errorMessage = "文件夹名称不能包含 / 或 \\。"
            return
        }
        guard canWrite else {
            errorMessage = "请先进入一个磁盘或文件夹。"
            return
        }
        do {
            let target = RemotePath.join(currentPath, trimmed)
            _ = try await session.makeDirectory(path: target)
            flash("已创建「\(trimmed)」")
            await load(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func download(_ entry: RemoteFileEntry) async {
        guard !entry.isDir else { return }
        guard downloadingPath == nil else { return }
        downloadingPath = entry.path
        errorMessage = nil
        do {
            let destination = localDestination(for: entry.path)
            let url = try await session.download(path: entry.path, to: destination)
            exportItem = ExportItem(url: url)
            flash("已下载 \(entry.name)")
        } catch {
            errorMessage = error.localizedDescription
        }
        downloadingPath = nil
    }

    func upload(url: URL) async -> Bool {
        guard canWrite else {
            errorMessage = "请先进入一个磁盘或文件夹。"
            return false
        }
        uploading = true
        errorMessage = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
            uploading = false
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let name = url.lastPathComponent.isEmpty ? "upload.bin" : url.lastPathComponent
            _ = try await session.upload(name: name, data: data, directory: currentPath)
            flash("已上传 \(name)")
            await load(path: currentPath)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ entry: RemoteFileEntry) async {
        do {
            _ = try await session.delete(path: entry.path)
            flash("已删除 \(entry.name)")
            await load(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func localDestination(for remotePath: String) -> URL {
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let rawName = remotePath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? "download.bin"
        let name = rawName.isEmpty ? "download.bin" : rawName
        var destination = folder.appendingPathComponent(name)
        if manager.fileExists(atPath: destination.path) {
            let base = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            var index = 1
            repeat {
                let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
                destination = folder.appendingPathComponent(candidate)
                index += 1
            } while manager.fileExists(atPath: destination.path)
        }
        return destination
    }

    private func isDriveRoot(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.count == 3
            && normalized.hasSuffix(":/")
            && normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":"
    }

    private func flash(_ text: String) {
        actionMessage = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self?.actionMessage == text {
                self?.actionMessage = nil
            }
        }
    }
}
