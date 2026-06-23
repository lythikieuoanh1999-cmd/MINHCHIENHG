import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Allowed file types
private let kAllowedTypes: [UTType] = [
    .image, .jpeg, .png, .gif, .webP, .heic,
    .pdf,
    .plainText, .utf8PlainText,
    .sourceCode, .swiftSource, .pythonScript, .shellScript, .javaScript,
    .json, .xml, .yaml,
    .data,   // fallback – allows ANY file
]

struct ChatView: View {
    @EnvironmentObject var store: AppStore

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var conversationId: Int?
    @State private var sending = false
    @State private var error: String?
    @State private var savedNotice: String?

    @State private var provider = ""
    @State private var model: String?
    @State private var ensembleOn = false
    @State private var ensembleProviders: Set<String> = []
    @State private var showAISheet = false

    // Attachment state
    @State private var photoItem: PhotosPickerItem?
    @State private var imageBase64: String?
    @State private var fileBase64: String?
    @State private var fileMime: String?
    @State private var attachmentName: String?

    // ✅ FIX: showFileImporter is reset properly after every result (success OR cancel)
    @State private var showFileImporter = false

    @StateObject private var recorder = VoiceRecorder()

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                messagesList
                if let attachmentName { attachmentChip(attachmentName) }
                if let savedNotice { savedFileChip(savedNotice) }
                inputBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("KENIOS").font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newChat() } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .sheet(isPresented: $showAISheet) {
                AISelectionView(provider: $provider, model: $model,
                                ensembleOn: $ensembleOn, ensembleProviders: $ensembleProviders)
            }
            .alert("Lỗi", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onAppear { if provider.isEmpty { setDefaultProvider() }; load() }
            .onChange(of: store.activeConversation) { _ in load() }
            .onChange(of: photoItem) { item in loadPhoto(item) }
            // ✅ FIX: use the correct fileImporter API that handles cancel properly
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: kAllowedTypes,
                allowsMultipleSelection: true
            ) { result in
                // Always reset the binding so the sheet can be reopened
                showFileImporter = false
                handleFileImport(result)
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.activeConversation?.title ?? "Hội thoại mới")
                    .font(.subheadline).bold().lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(providerColor(provider)).frame(width: 8, height: 8)
                    Text(ensembleOn
                         ? "Đối xứng \(ensembleProviders.count) AI"
                         : (providerLabel(provider) + (isFree(provider) ? " · Free" : "")))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { showAISheet = true } label: {
                Text("Chọn AI").font(.subheadline).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    // MARK: - Messages list
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 44))
                            .foregroundStyle(LinearGradient(
                                colors: [.blue, Theme.purple, .pink],
                                startPoint: .leading, endPoint: .trailing))
                        Text("Hôm nay bạn cần gì?")
                            .font(.title3).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 90)
                }
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { m in MessageBubble(message: m).id(m.id) }
                    if sending {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text(ensembleOn ? "Các AI đang trả lời..." : "Đang trả lời...")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.leading, 4)
                    }
                    if !sending, messages.last?.role == "assistant" {
                        Button { Task { await regenerate() } } label: {
                            Label("Tạo lại câu trả lời", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 2)
                    }
                }.padding()
            }
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Attachment chips
    private func attachmentChip(_ name: String) -> some View {
        HStack {
            Image(systemName: attachmentIcon(name))
                .foregroundStyle(Theme.accent)
            Text(name).lineLimit(1).font(.footnote)
            Spacer()
            Button { clearAttachment() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal).padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func attachmentIcon(_ name: String) -> String {
        let ext = name.split(separator: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "py", "js", "ts", "swift", "sh", "html", "css", "json": return "chevron.left.forwardslash.chevron.right"
        default: return "paperclip"
        }
    }

    private func savedFileChip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "doc.badge.checkmark").foregroundStyle(.green)
            Text(text).lineLimit(2)
            Spacer()
            Button { savedNotice = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .font(.caption).padding(.horizontal).padding(.vertical, 6)
        .background(Color.green.opacity(0.12))
    }

    // MARK: - Input bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            // ✅ FIX: Menu with proper tap targets — file importer triggered via button, not nested inside PhotosPicker
            Menu {
                // Tệp / Drive
                Button {
                    // ✅ FIX: Small delay prevents SwiftUI state conflict when dismissing Menu then presenting sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showFileImporter = true
                    }
                } label: {
                    Label("Tệp / Drive", systemImage: "folder")
                }

                // Ảnh từ thư viện
                // PhotosPicker must be a label inside Menu — we use a nested picker trick
                photosPickerMenuItem

            } label: {
                Image(systemName: "plus").font(.title3.bold())
                    .frame(width: 34, height: 34)
                    .kGlassInteractive(Circle())
            }

            TextField("Hỏi gì đó...", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .kGlass(RoundedRectangle(cornerRadius: 22))

            // Voice
            Button { toggleVoice() } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(recorder.isRecording ? .red : .secondary)
            }

            // Send
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent)
                    .clipShape(Circle())
            }
            .disabled(sending || (input.trimmingCharacters(in: .whitespaces).isEmpty
                                   && imageBase64 == nil && fileBase64 == nil))
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    // Isolated PhotosPicker as a menu item (avoids conflict with fileImporter)
    @ViewBuilder
    private var photosPickerMenuItem: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Ảnh", systemImage: "photo")
        }
    }

    // MARK: - Helpers
    private func providerLabel(_ id: String) -> String {
        store.providers.first(where: { $0.id == id })?.label ?? (id.isEmpty ? "Chọn AI" : id)
    }
    private func isFree(_ id: String) -> Bool {
        store.providers.first(where: { $0.id == id })?.free ?? false
    }
    private func setDefaultProvider() {
        provider = store.configuredKeys.first
            ?? store.providers.first(where: { $0.free })?.id
            ?? store.providers.first?.id ?? "gemini"
    }
    private func newChat() { store.activeConversation = nil; load() }
    private func load() {
        conversationId = store.activeConversation?.id
        messages = []
        if let cid = conversationId {
            Task { @MainActor in
                if let d = try? await store.api.conversation(cid) { messages = d.messages }
            }
        }
    }

    // MARK: - Send
    @MainActor private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || imageBase64 != nil || fileBase64 != nil else { return }
        sending = true; error = nil
        let attachLabel = imageBase64 != nil ? "[ảnh]" : (fileBase64 != nil ? "[file]" : "")
        messages.append(ChatMessage(role: "user", content: text.isEmpty ? attachLabel : text))
        let img = imageBase64
        let fb64 = fileBase64
        let fmime = fileMime
        input = ""; clearAttachment()
        do {
            if ensembleOn {
                guard ensembleProviders.count >= 2 else {
                    throw APIError.message("Chọn ít nhất 2 AI (đã nhập key) để đối xứng.")
                }
                let r = try await store.api.ensemble(providers: Array(ensembleProviders),
                                                     message: text, judge: nil)
                messages.append(ChatMessage(role: "assistant", content: r.best, provider: "ensemble"))
            } else {
                guard store.configuredKeys.contains(provider) else {
                    throw APIError.message("Chưa nhập API key cho \(providerLabel(provider)). Vào Cài đặt để thêm.")
                }
                let r = try await store.api.chat(
                    provider: provider, message: text,
                    image: img, fileBase64: fb64, fileMime: fmime,
                    model: model, conversationId: conversationId,
                    system: store.systemPrompt.isEmpty ? nil : store.systemPrompt
                )
                conversationId = r.conversationId
                messages.append(ChatMessage(role: "assistant", content: r.reply, provider: provider))
                if let files = r.savedFiles, !files.isEmpty {
                    savedNotice = "Đã tự lưu \(files.count) file → "
                        + files.map { $0.name }.joined(separator: ", ")
                }
                await store.refreshConversations()
            }
        } catch { self.error = error.localizedDescription }
        sending = false
    }

    // MARK: - Regenerate
    @MainActor private func regenerate() async {
        guard let lastUser = messages.last(where: { $0.role == "user" }) else { return }
        if messages.last?.role == "assistant" { messages.removeLast() }
        sending = true; error = nil
        do {
            if ensembleOn {
                let r = try await store.api.ensemble(providers: Array(ensembleProviders),
                                                     message: lastUser.content, judge: nil)
                messages.append(ChatMessage(role: "assistant", content: r.best, provider: "ensemble"))
            } else {
                let r = try await store.api.chat(
                    provider: provider, message: lastUser.content,
                    image: nil, model: model, conversationId: conversationId,
                    system: store.systemPrompt.isEmpty ? nil : store.systemPrompt
                )
                conversationId = r.conversationId
                messages.append(ChatMessage(role: "assistant", content: r.reply, provider: provider))
            }
        } catch { self.error = error.localizedDescription }
        sending = false
    }

    // MARK: - Photo picker
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self) {
                imageBase64 = data.base64EncodedString()
                attachmentName = "Ảnh đã chọn"
                fileBase64 = nil; fileMime = nil  // clear any prior file
            }
        }
    }

    // MARK: - File importer
    // ✅ FIX: Handles cancel gracefully (result is .failure with CocoaError.userCancelled)
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            var textCount = 0
            var firstFileName: String?

            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }

                guard let data = try? Data(contentsOf: url) else { continue }
                let uti = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)

                if uti?.conforms(to: .image) == true {
                    // Image → send as image_base64
                    if imageBase64 == nil {
                        imageBase64 = data.base64EncodedString()
                        attachmentName = url.lastPathComponent
                        fileBase64 = nil; fileMime = nil
                        firstFileName = url.lastPathComponent
                    }
                } else if uti?.conforms(to: .pdf) == true {
                    // PDF → file_base64
                    if fileBase64 == nil {
                        fileBase64 = data.base64EncodedString()
                        fileMime = "application/pdf"
                        attachmentName = url.lastPathComponent
                        firstFileName = url.lastPathComponent
                    }
                } else if let txt = String(data: data, encoding: .utf8) {
                    // Text / source code → paste inline
                    let label = url.lastPathComponent
                    input += "\n\n[Tệp \(label)]:\n" + txt.prefix(8000)
                    textCount += 1
                    if firstFileName == nil { firstFileName = label }
                } else {
                    // Binary file
                    if fileBase64 == nil {
                        fileBase64 = data.base64EncodedString()
                        fileMime = uti?.preferredMIMEType ?? "application/octet-stream"
                        attachmentName = url.lastPathComponent
                        firstFileName = url.lastPathComponent
                    }
                }
            }

            // Summary chip when only text files were added
            if textCount > 0 && attachmentName == nil {
                attachmentName = textCount == 1
                    ? "Đã thêm \(firstFileName ?? "tệp") vào tin nhắn"
                    : "Đã thêm \(textCount) tệp vào tin nhắn"
            }

        case .failure(let e):
            // User tapped "Không chọn" / cancelled — silently ignore CocoaError.userCancelled
            let nsErr = e as NSError
            let isCancelled = nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSUserCancelledError
            if !isCancelled {
                error = e.localizedDescription
            }
        }
    }

    private func clearAttachment() {
        imageBase64 = nil; fileBase64 = nil; fileMime = nil
        attachmentName = nil; photoItem = nil
    }

    // MARK: - Voice
    private func toggleVoice() {
        if recorder.isRecording {
            guard let data = recorder.stop() else { return }
            Task { @MainActor in
                do {
                    let r = try await store.api.transcribe(
                        provider: "openai",
                        audioBase64: data.base64EncodedString(),
                        mime: "audio/m4a"
                    )
                    input += (input.isEmpty ? "" : " ") + r.text
                } catch { self.error = error.localizedDescription }
            }
        } else {
            recorder.requestPermission { granted in
                guard granted else { error = "Cần quyền micro."; return }
                do { try recorder.start() } catch { self.error = error.localizedDescription }
            }
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if !isUser, let p = message.provider {
                    HStack(spacing: 5) {
                        Circle().fill(providerColor(p)).frame(width: 7, height: 7)
                        Text(p == "ensemble" ? "Đối xứng" : p.capitalized)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(message.content)
                    .padding(12)
                    .background(isUser ? Theme.accent : Color(.secondarySystemBackground))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Sao chép", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: message.content) {
                            Label("Lưu / Chia sẻ", systemImage: "square.and.arrow.up")
                        }
                    }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
