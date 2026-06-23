import SwiftUI

struct PaymentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var packages: [PaymentPackage] = []
    @State private var history: [PaymentRecord] = []
    @State private var created: PaymentCreateResponse?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Credits hiện tại") {
                    HStack {
                        Text(store.plan == "pro" ? "Gói PRO" : "Gói Free")
                        Spacer()
                        Text("\(store.credits) credits").foregroundStyle(Theme.accent).bold()
                    }
                }

                Section("Chọn gói nạp") {
                    ForEach(packages) { p in
                        Button {
                            Task { await create(p) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(p.label).foregroundStyle(.primary)
                                    Text("\(p.credits) credits").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if loading { ProgressView() }
                                else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(loading)
                    }
                }

                if let created {
                    Section("Quét mã QR để chuyển khoản") {
                        if let qr = created.qrUrl, let url = URL(string: qr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit()
                                        .frame(maxWidth: 280).frame(maxWidth: .infinity)
                                case .failure:
                                    Text("Không tải được mã QR. Dùng số tài khoản bên dưới.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                default:
                                    ProgressView().frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    Section("Thông tin chuyển khoản") {
                        LabeledContent("Ngân hàng", value: created.bankInfo.bank)
                        LabeledContent("Số tài khoản", value: created.bankInfo.account)
                        LabeledContent("Chủ tài khoản", value: created.bankInfo.name)
                        LabeledContent("Nội dung CK", value: created.bankInfo.content)
                        LabeledContent("Số tiền", value: "\(created.amount) đ")
                        Text(created.message).font(.footnote).foregroundStyle(.secondary)
                        Text("Sau khi chuyển khoản, admin sẽ xác nhận và cộng credits cho bạn.")
                            .font(.footnote).foregroundStyle(Theme.accent)
                    }
                }

                Section("Lịch sử nạp") {
                    if history.isEmpty {
                        Text("Chưa có giao dịch nào.").foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { h in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(h.amount) đ → \(h.credits) credits")
                                    Text(h.ref ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                statusBadge(h.status)
                            }
                        }
                    }
                }

                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Nạp Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = status == "completed"
            ? ("Đã cộng", .green) : (status == "pending" ? ("Chờ xác nhận", .orange) : (status, .secondary))
        return Text(text).font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18)).foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func load() async {
        error = nil
        do {
            packages = try await store.api.paymentPackages()
            history = try await store.api.paymentHistory()
        } catch { self.error = error.localizedDescription }
    }

    private func create(_ p: PaymentPackage) async {
        loading = true; error = nil
        do {
            created = try await store.api.createPayment(package: p.id, amount: p.amount)
            history = try await store.api.paymentHistory()
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
