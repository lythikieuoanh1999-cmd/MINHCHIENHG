import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var seg = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $seg) {
                    Text("Lịch sử").tag(0)
                    Text("File").tag(1)
                }
                .pickerStyle(.segmented).padding()
                if seg == 0 { HistoryPane() } else { FilesPane() }
            }
            .navigationTitle("Thư viện")
        }
    }
}

struct HistoryPane: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""

    private var filtered: [Conversation] {
        guard !search.isEmpty else { return store.conversations }
        return store.conversations.filter { ($0.title ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Tìm kiếm...", text: $search)
            }
            Button {
                store.openConversation(nil)
            } label: {
                Label("Hội thoại mới", systemImage: "plus").foregroundStyle(Theme.accent)
            }
            ForEach(filtered) { c in
                Button { store.openConversation(c) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.title ?? "Hội thoại").foregroundStyle(.primary).lineLimit(1)
                        if let p = c.provider {
                            HStack(spacing: 5) {
                                Circle().fill(providerColor(p)).frame(width: 7, height: 7)
                                Text(p.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .task { await store.refreshConversations() }
        .refreshable { await store.refreshConversations() }
        .overlay {
            if store.conversations.isEmpty {
                Text("Bạn chưa lưu cuộc trò chuyện nào").foregroundStyle(.secondary)
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        let ids = offsets.map { filtered[$0].id }
        Task {
            for id in ids { _ = try? await store.api.deleteConversation(id) }
            await store.refreshConversations()
        }
    }
}

struct FilesPane: View {
    @EnvironmentObject var store: AppStore
    @State private var category = "all"
    @State private var files: [FileItem] = []
    @State private var showImporter = false
    @State private var error: String?
    @State private var exportDoc: ExportableFile?
    @State private var runResult: FileRunResult?
    @State private var running: Int?

    private let cats = [("all", "Tất cả"), ("image", "Ảnh"), ("code", "Code"), ("document", "Tài liệu")]
    private let runnable: Set<String> = ["py", "js", "sh"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(cats, id: \.0) { c in
                        Button { category = c.0; Task { await reload() } } label: {
                            Text(c.1).font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(category == c.0 ? Theme.accent : Color(.secondarySystemBackground))
                                .foregroundStyle(category == c.0 ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }.padding(.horizontal)
            }
            List {
                ForEach(files) { f in
                    HStack {
                        Image(systemName: categoryIcon(f.category)).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text(f.name).lineLimit(1)
                            Text(humanSize(f.size)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isRunnable(f.name) {
                            Button {
                                Task { await run(f) }
                            } label: {
                                if running == f.id { ProgressView() }
                                else { Image(systemName: "play.circle") }
                            }
                            .disabled(running != nil)
                        }
                        Button { Task { await download(f) } } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
                .onDelete(perform: deleteFiles)

                Button { showImporter = true } label: {
                    VStack {
                        Label("Tải file lên từ máy", systemImage: "plus")
                        Text("Ảnh · PDF · Code · Tài liệu").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .task { await reload() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item], allowsMultipleSelection: false) { handleImport($0) }
        .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                      document: exportDoc, contentType: .data,
                      defaultFilename: exportDoc?.filename ?? "file") { _ in exportDoc = nil }
        .alert("Lỗi", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(item: $runResult) { r in RunResultView(result: r) }
    }

    private func isRunnable(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return runnable.contains(ext)
    }

    private func run(_ f: FileItem) async {
        running = f.id; error = nil
        do {
            runResult = try await store.api.runTestFile(fileId: f.id)
        } catch { self.error = error.localizedDescription }
        running = nil
    }

    private func reload() async {
        if let list = try? await store.api.listFiles(category: category) { files = list }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let cat: String
        if ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext) { cat = "image" }
        else if ["swift", "py", "js", "ts", "java", "c", "cpp", "go", "rs", "rb", "json", "html", "css"].contains(ext) { cat = "code" }
        else if ["pdf", "doc", "docx", "txt", "md", "xls", "xlsx", "ppt", "pptx"].contains(ext) { cat = "document" }
        else { cat = "other" }
        Task {
            do {
                _ = try await store.api.uploadFile(name: url.lastPathComponent, category: cat,
                                                   dataBase64: data.base64EncodedString())
                await reload()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func download(_ f: FileItem) async {
        do {
            let d = try await store.api.downloadFile(f.id)
            guard let data = Data(base64Encoded: d.dataBase64) else { return }
            exportDoc = ExportableFile(data: data, filename: d.name)
        } catch { self.error = error.localizedDescription }
    }

    private func deleteFiles(_ offsets: IndexSet) {
        let ids = offsets.map { files[$0].id }
        Task {
            for id in ids { _ = try? await store.api.deleteFile(id) }
            await reload()
        }
    }
}

struct RunResultView: View {
    @Environment(\.dismiss) var dismiss
    let result: FileRunResult

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(result.file).font(.subheadline.bold())
                        Spacer()
                        Text("returncode: \(result.returncode)")
                            .font(.caption).foregroundStyle(result.returncode == 0 ? .green : .red)
                    }
                    if !result.stdout.isEmpty {
                        Text("stdout").font(.caption).foregroundStyle(.secondary)
                        Text(result.stdout)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                    }
                    if !result.stderr.isEmpty {
                        Text("stderr").font(.caption).foregroundStyle(.secondary)
                        Text(result.stderr)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.red)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                    }
                    if result.stdout.isEmpty && result.stderr.isEmpty {
                        Text("Không có đầu ra.").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Kết quả chạy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
}

struct ExportableFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    var filename: String
    init(data: Data, filename: String) { self.data = data; self.filename = filename }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data(); filename = "file"
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
