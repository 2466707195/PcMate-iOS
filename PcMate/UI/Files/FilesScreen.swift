import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

struct FilesScreen: View {

    @StateObject private var model: FilesModel
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var deleteTarget: RemoteFileEntry?

    init(session: SessionController) {
        _model = StateObject(wrappedValue: FilesModel(session: session))
    }

    var body: some View {
        ZStack {
            AuroraBackdrop()
            AuroraScreen {
                AppTopBar(
                    title: "文件传输",
                    subtitle: model.currentPath.isEmpty ? "此电脑" : model.currentPath,
                    onBack: { dismiss() }
                ) {
                    HStack(spacing: 6) {
                        AuroraIconButton(
                            systemIcon: "arrow.clockwise",
                            tone: Aurora.brand,
                            enabled: !model.loading
                        ) {
                            Task { await model.load() }
                        }

                        Menu {
                            Button {
                                newFolderName = ""
                                showNewFolder = true
                            } label: {
                                Label("新建文件夹", systemImage: "folder.badge.plus")
                            }
                            .disabled(!model.canWrite)
                            Button {
                                showImporter = true
                            } label: {
                                Label("上传文件", systemImage: "arrow.up.doc")
                            }
                            .disabled(!model.canWrite)
                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("上传图片", systemImage: "photo.on.rectangle.angled")
                            }
                            .disabled(!model.canWrite)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Aurora.inkSoft)
                                .frame(width: 40, height: 40)
                                .auroraGlassSurface(
                                    Circle(),
                                    tone: Aurora.inkSoft,
                                    tint: 0,
                                    border: 0.16,
                                    shadowRadius: 0
                                )
                                .contentShape(Circle())
                        }
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 148) {
                    pathCard

                    if let action = model.actionMessage {
                        AuroraBanner(
                            systemIcon: "checkmark.circle.fill",
                            text: action,
                            tone: Aurora.success
                        )
                    }
                    if let error = model.errorMessage {
                        AuroraBanner(
                            systemIcon: "exclamationmark.triangle.fill",
                            text: error,
                            tone: Aurora.rose
                        )
                    }
                    if model.uploading {
                        SectionCard {
                            HStack(spacing: 10) {
                                ProgressView().tint(Aurora.brand)
                                Text("正在上传到电脑…")
                                    .font(AuroraFont.bodySmall)
                                    .foregroundStyle(Aurora.inkSoft)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    fileList
                }
            } bar: {
                GlassBar {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Aurora.brand)
                        Text(model.currentPath.isEmpty ? "此电脑" : model.currentPath)
                            .font(AuroraFont.bodySmall)
                            .foregroundStyle(Aurora.inkSoft)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        StatusPill(text: "\(model.entries.count) 项", color: Aurora.info)
                    }
                    Spacer().frame(height: 10)
                    HStack(spacing: 6) {
                        SmallTonalButton(
                            text: "上一级",
                            systemIcon: "arrow.up",
                            enabled: model.canGoUp,
                            expands: true,
                            height: 34
                        ) {
                            Task { await model.goUp() }
                        }
                        SmallTonalButton(
                            text: "新建",
                            systemIcon: "folder.badge.plus",
                            enabled: model.canWrite,
                            expands: true,
                            height: 34
                        ) {
                            newFolderName = ""
                            showNewFolder = true
                        }
                        SmallTonalButton(
                            text: "上传文件",
                            systemIcon: "arrow.up.doc",
                            enabled: model.canWrite,
                            expands: true,
                            height: 34
                        ) {
                            showImporter = true
                        }
                        SmallTonalButton(
                            text: "上传图片",
                            systemIcon: "photo.on.rectangle.angled",
                            enabled: model.canWrite,
                            expands: true,
                            height: 34
                        ) {
                            showPhotoPicker = true
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if model.listing == nil {
                Task { await model.load() }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    for url in urls {
                        _ = await model.upload(url: url)
                    }
                }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 20,
            matching: .images
        )
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await uploadPhotos(items) }
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") {
                let name = newFolderName
                newFolderName = ""
                Task { await model.makeDirectory(name: name) }
            }
            Button("取消", role: .cancel) { newFolderName = "" }
        } message: {
            Text("将在当前目录下创建文件夹。")
        }
        .confirmationDialog(
            "删除这个项目？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("删除", role: .destructive) {
                Task {
                    await model.delete(target)
                    deleteTarget = nil
                }
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { target in
            Text(target.isDir ? "文件夹必须为空才能删除。" : "将从电脑上永久删除「\(target.name)」。")
        }
        .sheet(item: $model.exportItem) { item in
            DocumentExporter(url: item.url)
        }
    }

    private var pathCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Aurora.brand)
                    Text("当前位置")
                        .font(AuroraFont.labelMedium)
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer(minLength: 0)
                    Text("\(model.entries.count) 项")
                        .font(AuroraFont.labelSmall)
                        .foregroundStyle(Aurora.muted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(model.breadcrumbs) { crumb in
                            let selected = crumb.id == model.breadcrumbs.last?.id
                            Button {
                                Task { await model.load(path: crumb.path) }
                            } label: {
                                Text(crumb.title)
                                    .font(AuroraFont.labelMedium)
                                    .foregroundStyle(selected ? Aurora.onBrandContainer : Aurora.inkSoft)
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(selected ? Aurora.brandContainer : Aurora.surfaceVariant)
                                    )
                            }
                            .buttonStyle(.plain)

                            if !selected {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Aurora.muted)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }

                AuroraTextField(
                    placeholder: "在当前目录搜索",
                    text: $model.search,
                    systemIcon: "magnifyingglass"
                )
            }
        }
    }

    @ViewBuilder
    private var fileList: some View {
        if model.loading && model.listing == nil {
            SectionCard {
                HStack(spacing: 10) {
                    ProgressView().tint(Aurora.brand)
                    Text("正在读取文件列表…")
                        .font(AuroraFont.bodySmall)
                        .foregroundStyle(Aurora.inkSoft)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        } else if let listing = model.listing {
            if model.entries.isEmpty {
                SectionCard {
                    EmptyStateView(
                        systemIcon: model.search.isEmpty ? "folder" : "magnifyingglass",
                        title: model.search.isEmpty ? "这个文件夹是空的" : "没有匹配的文件",
                        message: model.search.isEmpty ? "可以从手机上传文件，或返回上一级。" : "换个关键词试试。"
                    ) {
                        if model.search.isEmpty && model.canWrite {
                            TonalButton(text: "上传文件", systemIcon: "arrow.up.doc") {
                                showImporter = true
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.vertical, 16)
                }
            } else {
                SectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("\(model.entries.count) 个项目")
                                .font(AuroraFont.labelSmall)
                                .foregroundStyle(Aurora.muted)
                            Spacer()
                            if listing.path.isEmpty {
                                Text("选择一个磁盘")
                                    .font(AuroraFont.labelSmall)
                                    .foregroundStyle(Aurora.muted)
                            }
                        }
                        .padding(.bottom, 4)

                        ForEach(model.entries) { entry in
                            Button {
                                if entry.isDir {
                                    Task { await model.load(path: entry.path) }
                                } else {
                                    Task { await model.download(entry) }
                                }
                            } label: {
                                FileRow(
                                    entry: entry,
                                    downloading: model.downloadingPath == entry.path
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.downloadingPath != nil)
                            .contextMenu {
                                if entry.isDir {
                                    Button {
                                        Task { await model.load(path: entry.path) }
                                    } label: {
                                        Label("打开", systemImage: "folder")
                                    }
                                } else {
                                    Button {
                                        Task { await model.download(entry) }
                                    } label: {
                                        Label("下载", systemImage: "arrow.down.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    deleteTarget = entry
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }

                            if entry.id != model.entries.last?.id {
                                Rectangle()
                                    .fill(Aurora.hairline)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        } else {
            // 既没在读取、又没有列表数据：不能什么都不画（那就是一片空白），给个能点的出口
            SectionCard {
                EmptyStateView(
                    systemIcon: "wifi.exclamationmark",
                    title: "没读到文件列表",
                    message: "和电脑的连接可能刚断了一下，点下面重新读取。"
                ) {
                    TonalButton(text: "重新读取", systemIcon: "arrow.clockwise") {
                        Task { await model.load(force: true) }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - 相册上传

    /// 相册里选的图：统一转成 JPEG（Windows 上直接能看），再按时间命名上传。
    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())

        for (index, item) in items.enumerated() {
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    model.errorMessage = "有一张图片读取失败，换一张试试。"
                    continue
                }

                let payload: Data
                let ext: String
                if let image = UIImage(data: raw), let jpeg = Self.uprightJPEG(image) {
                    payload = jpeg
                    ext = "jpg"
                } else {
                    payload = raw
                    ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                }

                let name = items.count == 1
                    ? "IMG_\(stamp).\(ext)"
                    : "IMG_\(stamp)_\(index + 1).\(ext)"

                _ = await model.upload(data: payload, name: name)
            } catch {
                model.errorMessage = "读取图片失败：\(error.localizedDescription)"
            }
        }
    }

    /// 按实际朝向重绘一遍再压成 JPEG —— 否则部分相机的照片传到电脑上是横的。
    private static func uprightJPEG(_ image: UIImage, quality: CGFloat = 0.92) -> Data? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let upright = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return upright.jpegData(compressionQuality: quality)
    }
}

private struct FileRow: View {

    let entry: RemoteFileEntry
    let downloading: Bool

    private var subtitle: String {
        if entry.isDir {
            return entry.modifiedMs > 0 ? "文件夹 · \(Fmt.date(entry.modifiedMs))" : "文件夹"
        }
        let size = Fmt.bytes(entry.sizeBytes)
        if entry.modifiedMs > 0 {
            return "\(size) · \(Fmt.date(entry.modifiedMs))"
        }
        return size
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill((entry.isDir ? Aurora.warning : Aurora.info).tint(0.12))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: entry.systemIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(entry.isDir ? Aurora.warning : Aurora.info)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(AuroraFont.labelLarge)
                    .foregroundStyle(Aurora.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AuroraFont.labelSmall)
                    .foregroundStyle(Aurora.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if downloading {
                ProgressView()
                    .tint(Aurora.brand)
            } else {
                Image(systemName: entry.isDir ? "chevron.right" : "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.isDir ? Aurora.muted : Aurora.brand)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct DocumentExporter: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
