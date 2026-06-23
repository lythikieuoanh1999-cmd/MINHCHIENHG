import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var type = "VPS"
    @State private var url = ""
    @State private var testMsg: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Kết nối đang dùng") {
                    if store.baseURL.isEmpty {
                        Text("Chưa kết nối").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Image(systemName: "globe").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading) {
                                Text(store.serverType).font(.caption).foregroundStyle(.secondary)
                                Text(store.baseURL).lineLimit(1)
                            }
                        }
                    }
                }

                Section("Máy chủ của bạn (VPS / Hosting riêng)") {
                    ForEach(store.profiles) { p in
                        Button { store.selectProfile(p) } label: {
                            HStack {
                                Circle().fill(p.type == "VPS" ? Theme.accent : Theme.purple)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading) {
                                    Text(p.name).foregroundStyle(.primary)
                                    Text("\(p.type) · \(p.url)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if p.url == store.baseURL { Image(systemName: "checkmark").foregroundStyle(.green) }
                            }
                        }
                    }
                    .onDelete { idx in idx.map { store.profiles[$0] }.forEach { store.deleteProfile($0) } }
                }

                Section("Thêm máy chủ mới") {
                    Picker("Loại", selection: $type) {
                        Text("VPS").tag("VPS"); Text("Hosting").tag("Hosting")
                    }.pickerStyle(.segmented)
                    TextField("Tên gợi nhớ (vd: VPS của tôi)", text: $name)
                    TextField("IP / URL (vd: http://1.2.3.4:8000)", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button {
                        Task { await testAndAdd() }
                    } label: {
                        HStack { if testing { ProgressView().padding(.trailing, 6) }; Text("Kiểm tra & Thêm") }
                    }.disabled(url.isEmpty || name.isEmpty || testing)
                    if let testMsg { Text(testMsg).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Kết nối máy chủ")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
        }
    }

    private func testAndAdd() async {
        testing = true; testMsg = nil
        let ok = (try? await APIClient(baseURL: url, token: nil).getConfig()) != nil
        if ok {
            store.addProfile(name: name, type: type, url: url)
            name = ""; url = ""; testMsg = "Đã thêm & kết nối."
        } else {
            testMsg = "Không kết nối được. Kiểm tra IP/URL."
        }
        testing = false
    }
}
