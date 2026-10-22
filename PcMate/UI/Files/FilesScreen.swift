import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilesScreen: View {

    @StateObject private var model: FilesModel
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
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
                    HStack(spacing: 2) {
                        Button {
                            Task { await model.load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Aurora.brand)
                                .frame(width: 38, height: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.loading)

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
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Aurora.inkSoft)
                                .frame(width: 38, height: 38)
                                .contentShape(Rectangle())
                        }
                    }
                }
            } content: {
                AuroraScrollView(bottomInset: 150) {
                    breadcrumbBar
                    searchField

                    if let action = model.actionMessage {
                        banner(icon: "checkmark.circle.fill", text: action, color: Aurora.success, background: Aurora.successContainer)
                    }
                    if let error = model.errorMessage {
                        banner(icon: "exclamationmark.triangle.fill", text: error, color: Aurora.rose, background: Aurora.roseContainer)
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
                    HStack(spacing: 8) {
                        SmallTonalButton(text: "上一级", systemIcon: "arrow.up", enabled: model.canGoUp, expands: true) {
                            Task { await model.goUp() }
                        }
                        SmallTonalButton(text: "新建", systemIcon: "folder.badge.plus", enabled: model.canWrite, expands: true) {
                            newFolderName = ""
                            showNewFolder = true
                        }
                        SmallTonalButton(text: "上传", systemIcon: "arrow.up.doc", enabled: model.canWrite, expands: true) {
                            showImporter = true
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

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(model.breadcrumbs) { crumb in
                    Button {
                        Task { await model.load(path: crumb.path) }
                    } label: {
                        Text(crumb.title)
                            .font(AuroraFont.labelMedium)
                            .foregroundStyle(crumb.id == model.breadcrumbs.last?.id ? Aurora.ink : Aurora.brand)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(crumb.id == model.breadcrumbs.last?.id ? Aurora.surfaceVariant : Aurora.brandContainer.opacity(0.7))
                            )
                    }
                    .buttonStyle(.plain)

                    if crumb.id != model.breadcrumbs.last?.id {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Aurora.muted)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var searchField: some View {
        AuroraTextField(
            placeholder: "在当前目录搜索",
            text: $model.search,
            systemIcon: "magnifyingglass"
        )
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
        }
    }

    private func banner(icon: String, text: String, color: Color, background: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(AuroraFont.bodySmall)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
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
