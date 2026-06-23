import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var email = ""
    @State private var phone = ""
    @State private var newPassword = ""
    @State private var message: String?
    @State private var connected: Bool?
    @State private var keyProvider: Provider?
    @State private var showConnections = false
    @State private var showPayment = false

    var body: some View {
        NavigationStack {
            Form {
                // API KEYS
                Section {
                    ForEach(store.providers) { p in
                        Button { keyProvider = p } label: {
                            HStack {
                                Circle().fill(providerColor(p.id)).frame(width: 10, height: 10)
                                Text(p.label.components(separatedBy: " · ").first ?? p.id)
                                    .foregroundStyle(.primary)
                                if p.free {
                                    Text("Free").font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2)).foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                if store.configuredKeys.contains(p.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                } else {
                                    Text("Chưa có").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("API Keys")
                } footer: {
                    Text("Key được mã hóa (Fernet) khi lưu trên máy chủ. AI có key sẽ hiện ra để chọn khi chat.")
                }

                // SERVER
                Section("Kết nối máy chủ (\(store.serverType))") {
                    LabeledContent("URL / IP", value: store.baseURL)
                    HStack {
                        Text("Trạng thái")
                        Spacer()
                        if let connected {
                            Circle().fill(connected ? .green : .red).frame(width: 8, height: 8)
                            Text(connected ? "Đang kết nối" : "Mất kết nối")
                                .foregroundStyle(connected ? .green : .red)
                        } else { ProgressView() }
                    }
                    Button("Quản lý máy chủ (VPS / Hosting)") { showConnections = true }
                }

                // ACCOUNT
                Section("Tài khoản") {
                    LabeledContent("Tên đăng nhập", value: store.username ?? "-")
                    HStack {
                        Text("Gói")
                        Spacer()
                        Text(store.plan == "pro" ? "PRO" : "Free")
                            .foregroundStyle(store.plan == "pro" ? .green : .secondary)
                    }
                    HStack {
                        Text("Credits")
                        Spacer()
                        Text("\(store.credits)").foregroundStyle(Theme.accent)
                    }
                    Button("Nạp credits") { showPayment = true }
                    TextField("Gmail", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField("Số điện thoại", text: $phone).keyboardType(.phonePad)
                    SecureField("Đổi mật khẩu (để trống nếu không đổi)", text: $newPassword)
                    Button("Lưu thay đổi") { Task { await saveProfile() } }
                }

                // OTHER
                Section("Vai trò AI (tùy chọn)") {
                    TextField("VD: Bạn là trợ lý lập trình, trả lời ngắn gọn bằng tiếng Việt...",
                              text: Binding(get: { store.systemPrompt },
                                            set: { store.setSystemPrompt($0) }),
                              axis: .vertical)
                        .lineLimit(2...5)
                    Text("Hướng dẫn này được gửi kèm mỗi lần chat để AI trả lời theo đúng phong cách/vai trò bạn muốn. Để trống nếu không cần.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Khác") {
                    Picker("Ngôn ngữ", selection: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) })) {
                        Text("Tiếng Việt").tag("vi")
                        Text("English").tag("en")
                    }
                    Toggle("Giao diện tối", isOn: Binding(
                        get: { store.isDark }, set: { store.setDark($0) }))
                }

                if let message { Text(message).foregroundStyle(.green).font(.footnote) }

                Section {
                    Button("Đăng xuất", role: .destructive) { store.logout() }
                }
            }
            .navigationTitle("Cài đặt")
            .sheet(item: $keyProvider) { p in KeyEntryView(provider: p) }
            .sheet(isPresented: $showConnections) { ConnectionsView() }
            .sheet(isPresented: $showPayment) { PaymentView() }
            .task {
                await store.loadKeys()
                await store.refreshCredits()
                connected = (try? await store.api.getConfig()) != nil
            }
            .onAppear { email = store.email ?? ""; phone = store.phone ?? "" }
        }
    }

    private func saveProfile() async {
        do {
            _ = try await store.api.updateProfile(email: email, phone: phone,
                                                  newPassword: newPassword.isEmpty ? nil : newPassword)
            store.updateLocalUser(email: email, phone: phone)
            newPassword = ""; message = "Đã cập nhật."
        } catch { message = error.localizedDescription }
    }
}

struct KeyEntryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let provider: Provider
    @State private var key = ""
    @State private var message: String?
    @State private var isError = false
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle().fill(providerColor(provider.id)).frame(width: 10, height: 10)
                        Text(provider.label).bold()
                        if provider.free {
                            Text("Free").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.2)).foregroundStyle(.green).clipShape(Capsule())
                        }
                    }
                    SecureField("Dán API key tại đây", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Model mặc định: \(provider.defaultModel)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if checking { ProgressView().padding(.trailing, 4) }
                            Text(checking ? "Đang kiểm tra key..." : "Lưu & kiểm tra key")
                        }
                    }
                    .disabled(key.isEmpty || checking)
                    if store.configuredKeys.contains(provider.id) {
                        Button("Xóa key", role: .destructive) { Task { await remove() } }
                    }
                }
                if let message {
                    Text(message).font(.footnote)
                        .foregroundStyle(isError ? .red : .green)
                }
            }
            .navigationTitle("Nhập API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }

    private func save() async {
        checking = true; message = nil
        do {
            _ = try await store.api.saveKey(provider: provider.id, apiKey: key)
            do {
                _ = try await store.api.testKey(provider: provider.id, apiKey: key)
                isError = false; message = "Key hợp lệ, đã lưu ✓"
                await store.loadKeys()
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            } catch {
                isError = true
                message = "Key đã lưu nhưng KHÔNG dùng được: \(error.localizedDescription)"
                await store.loadKeys()
            }
        } catch {
            isError = true; message = error.localizedDescription
        }
        checking = false
    }
    private func remove() async {
        do { _ = try await store.api.deleteKey(provider: provider.id)
            await store.loadKeys(); dismiss()
        } catch { message = error.localizedDescription }
    }
}
