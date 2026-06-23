import SwiftUI

struct AdminView: View {
    @EnvironmentObject var store: AppStore
    @State private var users: [AdminUser] = []
    @State private var error: String?
    @State private var message: String?
    @State private var pwUser: AdminUser?
    @State private var paymentId = ""
    @State private var showBank = false
    @State private var showErrors = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Quản trị tài khoản người dùng. Có thể khóa/mở, đổi mật khẩu giúp người dùng, đặt gói.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Hệ thống") {
                    Button { showBank = true } label: {
                        Label("Thông tin ngân hàng / nạp tiền", systemImage: "banknote")
                    }
                    Button { showErrors = true } label: {
                        Label("Log lỗi hệ thống", systemImage: "exclamationmark.triangle")
                    }
                }
                Section("Xác nhận thanh toán") {
                    HStack {
                        TextField("ID đơn thanh toán", text: $paymentId)
                            .keyboardType(.numberPad)
                        Button("Xác nhận") { Task { await confirmPayment() } }
                            .disabled(paymentId.isEmpty)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.green) }
                }
                ForEach(users) { u in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(u.username).bold()
                            if (u.isAdmin ?? 0) == 1 {
                                Text("admin").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.2)).foregroundStyle(Theme.accent)
                                    .clipShape(Capsule())
                            }
                            if u.plan == "pro" {
                                Text("PRO").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2)).foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if (u.banned ?? 0) == 1 {
                                Text("đã khóa").font(.caption).foregroundStyle(.red)
                            }
                        }
                        if let e = u.email, !e.isEmpty { Text(e).font(.caption).foregroundStyle(.secondary) }
                        if let p = u.phone, !p.isEmpty { Text(p).font(.caption).foregroundStyle(.secondary) }
                        Text("Credits: \(u.credits ?? 0)").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Menu("Thao tác") {
                                Button((u.banned ?? 0) == 1 ? "Mở khóa" : "Khóa tài khoản",
                                       role: (u.banned ?? 0) == 1 ? nil : .destructive) {
                                    Task { await ban(u, !(((u.banned ?? 0) == 1))) }
                                }
                                Button(u.plan == "pro" ? "Đặt về Free" : "Nâng lên Pro") {
                                    Task { await setPlan(u, u.plan == "pro" ? "free" : "pro") }
                                }
                                Button("Đổi mật khẩu giúp") { pwUser = u }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Quản trị")
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(item: $pwUser) { u in AdminPasswordSheet(user: u) { Task { await reload() } } }
            .sheet(isPresented: $showBank) { BankSettingsSheet() }
            .sheet(isPresented: $showErrors) { ErrorLogView() }
            .alert("Lỗi", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func confirmPayment() async {
        guard let pid = Int(paymentId) else { return }
        message = nil; error = nil
        do {
            let r = try await store.api.adminConfirmPayment(pid)
            message = r.message; paymentId = ""
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    private func reload() async {
        do { users = try await store.api.adminUsers() }
        catch { self.error = error.localizedDescription }
    }
    private func ban(_ u: AdminUser, _ banned: Bool) async {
        do { _ = try await store.api.adminBan(u.id, banned: banned); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func setPlan(_ u: AdminUser, _ plan: String) async {
        do { _ = try await store.api.adminSetPlan(u.id, plan: plan); await reload() }
        catch { self.error = error.localizedDescription }
    }
}

struct AdminPasswordSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let user: AdminUser
    var onDone: () -> Void
    @State private var newPassword = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Đổi mật khẩu cho \(user.username)") {
                    SecureField("Mật khẩu mới (≥6 ký tự)", text: $newPassword)
                    Button("Xác nhận") { Task { await save() } }.disabled(newPassword.count < 6)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Đổi mật khẩu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
    private func save() async {
        do {
            _ = try await store.api.adminSetPassword(user.id, newPassword: newPassword)
            onDone(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// ======================== Cài đặt ngân hàng (admin) ========================
struct BankSettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var s = BankSettings(bankCode: "970416", bankShort: "ACB",
                                        bankAccount: "23252921", bankName: "TRAN MINH CHIEN",
                                        bankWebhook: "", bankApikey: "")
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ngân hàng nhận tiền (hiện QR cho khách khi nạp)") {
                    TextField("Mã ngân hàng VietQR (vd ACB = 970416)", text: $s.bankCode)
                        .keyboardType(.numberPad)
                    TextField("Tên ngân hàng ngắn (vd ACB)", text: $s.bankShort)
                        .textInputAutocapitalization(.characters)
                    TextField("Số tài khoản", text: $s.bankAccount).keyboardType(.numberPad)
                    TextField("Chủ tài khoản (IN HOA, không dấu)", text: $s.bankName)
                        .textInputAutocapitalization(.characters)
                    TextField("Webhook (tuỳ chọn)", text: $s.bankWebhook)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Tự động xác nhận giao dịch (tuỳ chọn)") {
                    TextField("API key giao dịch (Casso / Sepay...)", text: $s.bankApikey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Nhập API key của dịch vụ đọc biến động số dư (vd Casso, Sepay) để tự động cộng credits khi khách chuyển khoản. Để trống thì admin xác nhận tay.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Lưu") { Task { await save() } } }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(isError ? .red : .green)
                }
                Section {
                    Text("Mã VietQR (Napas): ACB 970416 · Vietcombank 970436 · Techcombank 970407 · MB 970422 · BIDV 970418 · VPBank 970432.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Thông tin ngân hàng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        if let r = try? await store.api.adminGetBank() { s = r }
    }
    private func save() async {
        message = nil
        do { let r = try await store.api.adminSetBank(s); isError = false; message = r.message }
        catch { isError = true; message = error.localizedDescription }
    }
}

// ======================== Log lỗi hệ thống (admin) ========================
struct ErrorLogView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var logs: [ErrorLog] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if logs.isEmpty {
                    Text("Chưa có lỗi nào được ghi.").foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { e in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.context ?? "-").font(.caption.bold())
                            Text(e.detail ?? "").font(.caption2).foregroundStyle(.red)
                            HStack {
                                if let u = e.username { Text(u).font(.caption2).foregroundStyle(.secondary) }
                                Spacer()
                                Text(timeText(e.createdAt)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Log lỗi hệ thống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Xóa hết", role: .destructive) { Task { await clear() } }
                        .disabled(logs.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .alert("Lỗi", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func reload() async {
        do { logs = try await store.api.adminErrors() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func clear() async {
        do { _ = try await store.api.adminClearErrors(); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func timeText(_ ts: Int?) -> String {
        guard let ts else { return "" }
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
