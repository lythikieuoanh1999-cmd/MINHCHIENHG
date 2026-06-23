import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject var store: AppStore
    @State private var url = ""
    @State private var type = "VPS"
    @State private var testing = false
    @State private var message: String?
    @State private var ok = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Loại máy chủ", selection: $type) {
                        Text("VPS").tag("VPS")
                        Text("Hosting").tag("Hosting")
                    }
                    .pickerStyle(.segmented)

                    TextField("IP hoặc URL (vd: http://1.2.3.4:8000)", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Kết nối máy chủ")
                } footer: {
                    Text("Nhập địa chỉ máy chủ chạy codebox.py. Có thể nhập IP có cổng, app sẽ tự thêm http:// nếu thiếu.")
                }

                if let message {
                    Text(message).foregroundStyle(ok ? .green : .red).font(.footnote)
                }

                Section {
                    Button {
                        Task { await testAndSave() }
                    } label: {
                        HStack {
                            if testing { ProgressView().padding(.trailing, 6) }
                            Text(testing ? "Đang kiểm tra..." : "Kiểm tra & Lưu")
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                }
            }
            .navigationTitle("KENIOS")
        }
    }

    private func testAndSave() async {
        testing = true; message = nil; ok = false
        let client = APIClient(baseURL: url, token: nil)
        do {
            let cfg = try await client.getConfig()
            ok = true
            message = "Kết nối OK · \(cfg.name) · \(cfg.providers.count) AI"
            store.addProfile(name: type == "VPS" ? "VPS của tôi" : "Hosting của tôi",
                             type: type, url: url)
        } catch {
            message = error.localizedDescription
        }
        testing = false
    }
}
