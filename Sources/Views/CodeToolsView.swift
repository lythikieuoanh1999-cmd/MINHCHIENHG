import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct CodeToolsView: View {
    @EnvironmentObject var store: AppStore
    @State private var seg = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $seg) {
                    Text("Chạy code").tag(0)
                    Text("AI lập trình").tag(1)
                    Text("Web/Game").tag(2)
                }
                .pickerStyle(.segmented).padding()
                if seg == 0 { RunPythonPane() }
                else if seg == 1 { CodeAIPane() }
                else { WebPreviewPane() }
            }
            .navigationTitle("Lập trình")
        }
    }
}

// ======================== Chạy Python trên server ========================
struct RunPythonPane: View {
    @EnvironmentObject var store: AppStore
    @State private var code = "print(\"Xin chào KENIOS!\")"
    @State private var stdin = ""
    @State private var result: CodeRunResult?
    @State private var running = false
    @State private var error: String?
    @State private var showImporter = false
    @State private var language = "python"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Code").font(.subheadline.bold())
                    Picker("", selection: $language) {
                        Text("Python").tag("python")
                        Text("JavaScript").tag("javascript")
                        Text("TypeScript").tag("typescript")
                        Text("Bash").tag("bash")
                        Text("PHP").tag("php")
                        Text("Ruby").tag("ruby")
                        Text("C").tag("c")
                        Text("C++").tag("cpp")
                        Text("Go").tag("go")
                        Text("Java").tag("java")
                        Text("Rust").tag("rust")
                    }.pickerStyle(.menu)
                    Spacer()
                    Button { showImporter = true } label: {
                        Label("Thêm tệp", systemImage: "doc.badge.plus").font(.caption)
                    }
                }
                TextEditor(text: $code)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if language == "java" {
                    Text("Java: lớp public phải đặt tên là Main (file Main.java).")
                        .font(.caption).foregroundStyle(.orange)
                }

                Text("Stdin (tuỳ chọn)").font(.subheadline.bold())
                TextField("Dữ liệu nhập cho input()...", text: $stdin, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if running { ProgressView().tint(.white).padding(.trailing, 4) }
                        Text("Chạy code").bold()
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Theme.accent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(running || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let result {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Kết quả").font(.subheadline.bold())
                            Button {
                                UIPasteboard.general.string = result.stdout + (result.stderr.isEmpty ? "" : "\n" + result.stderr)
                            } label: { Image(systemName: "doc.on.doc").font(.caption) }
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
                    }
                }

                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .padding()
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.sourceCode, .plainText, .text, .html, .json, .item],
                      allowsMultipleSelection: false) { loadFile($0) }
    }

    private func loadFile(_ res: Result<[URL], Error>) {
        guard case .success(let urls) = res, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            code = text
        } else {
            error = "Không đọc được file (có thể là file nhị phân, không phải text/code)."
        }
    }

    private func run() async {
        running = true; error = nil; result = nil
        do {
            result = try await store.api.runCode(language: language, code: code,
                                                 stdin: stdin.isEmpty ? nil : stdin)
        } catch { self.error = error.localizedDescription }
        running = false
    }
}

// ======================== AI lập trình (review/debug/explain/...) ========================
struct CodeAIPane: View {
    @EnvironmentObject var store: AppStore

    @State private var code = ""
    @State private var language = "python"
    @State private var task = "review"
    @State private var targetLang = "JavaScript"
    @State private var provider = ""
    @State private var result: String?
    @State private var running = false
    @State private var error: String?
    @State private var showImporter = false

    private let tasks: [(String, String)] = [
        ("review", "Review code"),
        ("debug", "Debug / sửa lỗi"),
        ("explain", "Giải thích"),
        ("convert", "Chuyển ngôn ngữ"),
        ("test", "Viết unit test"),
        ("optimize", "Tối ưu hiệu năng"),
        ("document", "Viết docstring"),
        ("security", "Kiểm tra bảo mật"),
    ]
    private let languages = ["python", "javascript", "typescript", "swift", "kotlin",
                              "go", "rust", "c", "cpp", "java", "php", "html", "css", "sql", "shell"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Dán code cần xử lý").font(.subheadline.bold())
                    Spacer()
                    Button { showImporter = true } label: {
                        Label("Thêm tệp", systemImage: "doc.badge.plus").font(.caption)
                    }
                }
                TextEditor(text: $code)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ngôn ngữ").font(.caption).foregroundStyle(.secondary)
                        Picker("Ngôn ngữ", selection: $language) {
                            ForEach(languages, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tác vụ").font(.caption).foregroundStyle(.secondary)
                        Picker("Tác vụ", selection: $task) {
                            ForEach(tasks, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                }

                if task == "convert" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chuyển sang").font(.caption).foregroundStyle(.secondary)
                        TextField("VD: JavaScript, Kotlin, Go...", text: $targetLang)
                            .padding(8).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI sử dụng").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(store.providers.filter { ($0.code ?? false) }) { p in
                                Button { provider = p.id } label: {
                                    HStack(spacing: 6) {
                                        if provider == p.id { Image(systemName: "checkmark").font(.caption2) }
                                        Circle().fill(providerColor(p.id)).frame(width: 7, height: 7)
                                        Text(p.label.components(separatedBy: " · ").first ?? p.id)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(provider == p.id ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                                    .opacity(store.configuredKeys.contains(p.id) ? 1 : 0.4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if running { ProgressView().tint(.white).padding(.trailing, 4) }
                        Text("Gửi cho AI").bold()
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Theme.accent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(running || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || provider.isEmpty || !store.configuredKeys.contains(provider))

                if !store.configuredKeys.contains(provider) && !provider.isEmpty {
                    Text("Chưa có API key cho AI này. Vào Cài đặt → API Keys.")
                        .font(.caption).foregroundStyle(.orange)
                }

                if let result {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kết quả").font(.subheadline.bold())
                        Text(result)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                            .contextMenu {
                                Button { UIPasteboard.general.string = result } label: {
                                    Label("Sao chép", systemImage: "doc.on.doc")
                                }
                            }
                    }
                }

                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .padding()
        }
        .onAppear {
            if provider.isEmpty {
                provider = store.configuredKeys.first(where: { id in
                    store.providers.first(where: { $0.id == id })?.code ?? false
                }) ?? store.providers.first(where: { $0.code ?? false })?.id ?? ""
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.sourceCode, .plainText, .text, .html, .json, .item],
                      allowsMultipleSelection: false) { loadFile($0) }
    }

    private func loadFile(_ res: Result<[URL], Error>) {
        guard case .success(let urls) = res, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            error = "Không đọc được file (có thể là file nhị phân, không phải text/code)."
            return
        }
        code = text
        let map = ["py": "python", "js": "javascript", "ts": "typescript", "swift": "swift",
                   "kt": "kotlin", "go": "go", "rs": "rust", "c": "c", "cpp": "cpp",
                   "java": "java", "php": "php", "html": "html", "css": "css", "sql": "sql", "sh": "shell"]
        if let l = map[(url.pathExtension).lowercased()] { language = l }
    }

    private func run() async {
        running = true; error = nil; result = nil
        do {
            let r = try await store.api.codeAI(provider: provider, code: code, language: language,
                                               task: task, targetLang: task == "convert" ? targetLang : nil)
            result = r.result
        } catch { self.error = error.localizedDescription }
        running = false
    }
}

// ======================== Xem trước Web / Game (giả lập trong app) ========================
struct WebPreview: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var last = "\u{1}" }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.scrollView.bounces = false
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {
        guard context.coordinator.last != html else { return }
        context.coordinator.last = html
        let content = html.isEmpty
            ? "<html><body style='font-family:-apple-system;color:#888;text-align:center;padding-top:40px'>Bấm \"Chạy thử\" để xem web/game ở đây.</body></html>"
            : html
        wv.loadHTMLString(content, baseURL: nil)
    }
}

struct WebPreviewPane: View {
    @EnvironmentObject var store: AppStore
    @State private var html = WebPreviewPane.sample
    @State private var preview = ""
    @State private var showImporter = false
    @State private var showFull = false
    @State private var gameDesc = ""
    @State private var provider = ""
    @State private var generating = false
    @State private var error: String?

    static let sample = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>body{font-family:-apple-system;text-align:center;padding:24px}
    button{font-size:20px;padding:12px 22px;border:none;border-radius:12px;background:#4f46e5;color:#fff}</style>
    </head><body><h2>KENIOS Web/Game</h2><p>Điểm: <b id="s">0</b></p>
    <button onclick="document.getElementById('s').innerText=++c">Bấm để tăng điểm</button>
    <script>let c=0</script></body></html>
    """

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("HTML / JS — web · game").font(.subheadline.bold())
                Spacer()
                Button { showImporter = true } label: {
                    Label("Thêm tệp", systemImage: "doc.badge.plus").font(.caption)
                }
            }
            TextEditor(text: $html)
                .font(.system(.footnote, design: .monospaced))
                .frame(height: 110)
                .padding(6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                TextField("Tả game muốn AI viết (vd: game rắn săn mồi)...", text: $gameDesc)
                    .padding(8).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button { Task { await generate() } } label: {
                    HStack(spacing: 4) {
                        if generating { ProgressView() }
                        else { Image(systemName: "wand.and.stars") }
                        Text("AI viết").font(.caption.bold())
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.accent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(generating || gameDesc.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Button { preview = html } label: {
                    Label("Chạy thử", systemImage: "play.fill").bold()
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button { preview = html; showFull = true } label: {
                    Label("Toàn màn hình", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ShareLink(item: webFileURL()) {
                    Label("Lưu file HTML về máy", systemImage: "square.and.arrow.down")
                        .font(.caption).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if let error { Text(error).foregroundStyle(.red).font(.caption) }

            WebPreview(html: preview)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))
        }
        .padding()
        .onAppear {
            if provider.isEmpty {
                provider = store.configuredKeys.first(where: { id in
                    store.providers.first(where: { $0.id == id })?.code ?? false
                }) ?? store.configuredKeys.first ?? ""
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.html, .plainText, .text, .sourceCode, .item],
                      allowsMultipleSelection: false) { loadFile($0) }
        .sheet(isPresented: $showFull) {
            NavigationStack {
                WebPreview(html: preview).ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Chơi thử").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { showFull = false } } }
            }
        }
    }

    private func webFileURL() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("kenios_web.html")
        try? html.data(using: .utf8)?.write(to: u)
        return u
    }

    private func loadFile(_ res: Result<[URL], Error>) {
        guard case .success(let urls) = res, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            html = text; preview = text
        } else { error = "Không đọc được file." }
    }

    private func generate() async {
        // Tự chọn AI có key nếu chưa có
        if provider.isEmpty {
            provider = store.configuredKeys.first(where: { id in
                store.providers.first(where: { $0.id == id })?.code ?? false
            }) ?? store.configuredKeys.first ?? ""
        }
        guard !provider.isEmpty else {
            error = "Chưa có AI nào có key. Vào Cài đặt → API Keys thêm key (vd Gemini hoặc Groq, miễn phí) rồi quay lại."
            return
        }
        generating = true; error = nil
        let prompt = """
        Viết một game/web hoàn chỉnh theo mô tả: "\(gameDesc)".
        Yêu cầu: TẤT CẢ trong MỘT file index.html duy nhất (HTML + CSS + JavaScript inline), không dùng thư viện ngoài, chạy được ngay trên trình duyệt điện thoại. Chỉ trả về code trong một khối ```html ... ```, không giải thích.
        """
        do {
            let r = try await store.api.chat(provider: provider, message: prompt, image: nil,
                                             model: nil, conversationId: nil, system: nil)
            let code = WebPreviewPane.extractCode(r.reply)
            html = code; preview = code
        } catch { self.error = error.localizedDescription }
        generating = false
    }

    static func extractCode(_ text: String) -> String {
        let parts = text.components(separatedBy: "```")
        guard parts.count >= 3 else { return text }
        var block = parts[1]
        if let nl = block.firstIndex(of: "\n") {
            let lang = block[..<nl].trimmingCharacters(in: .whitespaces)
            if lang.count < 20 && !lang.contains("<") {
                block = String(block[block.index(after: nl)...])
            }
        }
        return block.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
