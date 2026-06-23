import SwiftUI

struct AISelectionView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @Binding var provider: String
    @Binding var model: String?
    @Binding var ensembleOn: Bool
    @Binding var ensembleProviders: Set<String>

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Chọn AI").font(.headline)
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(store.providers) { p in chip(p) }
                    }

                    if let cur = store.providers.first(where: { $0.id == provider }) {
                        Text("Model").font(.subheadline).foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(Array(cur.models.enumerated()), id: \.offset) { idx, mdl in
                                Button {
                                    model = mdl
                                } label: {
                                    HStack {
                                        Text(mdl).foregroundStyle(.primary)
                                        Spacer()
                                        if (model ?? cur.defaultModel) == mdl {
                                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                        }
                                        badge(idx == 0 && cur.free ? "Free" : (idx == 0 ? "Smart" : "Fast"))
                                    }
                                    .padding(.vertical, 10)
                                }
                                if idx < cur.models.count - 1 { Divider() }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $ensembleOn) {
                            Text("Chế độ Đối xứng AI").font(.subheadline.bold())
                                .foregroundStyle(Theme.purple)
                        }
                        Text("Chọn nhiều AI cùng lúc · mỗi AI trả lời riêng → 1 AI tổng hợp ra câu tốt nhất")
                            .font(.caption).foregroundStyle(.secondary)
                        if ensembleOn {
                            LazyVGrid(columns: cols, spacing: 8) {
                                ForEach(store.providers.filter { store.configuredKeys.contains($0.id) }) { p in
                                    ensembleChip(p)
                                }
                            }
                            if store.configuredKeys.count < 2 {
                                Text("Cần nhập key cho ít nhất 2 AI ở Cài đặt.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding()
                    .background(Theme.purple.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding()
            }
            .navigationTitle("AI & Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
        }
    }

    private func chip(_ p: Provider) -> some View {
        let configured = store.configuredKeys.contains(p.id)
        let selected = provider == p.id && !ensembleOn
        return Button {
            guard configured else { return }
            provider = p.id; model = nil; ensembleOn = false
        } label: {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.caption2) }
                Circle().fill(providerColor(p.id)).frame(width: 8, height: 8)
                Text(p.label.components(separatedBy: " · ").first ?? p.id)
                    .font(.caption).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(selected ? Theme.accent : .clear, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .opacity(configured ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }

    private func ensembleChip(_ p: Provider) -> some View {
        let on = ensembleProviders.contains(p.id)
        return Button {
            if on { ensembleProviders.remove(p.id) } else { ensembleProviders.insert(p.id) }
        } label: {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark").font(.caption2) }
                Text(p.id).font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(on ? Theme.purple.opacity(0.4) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String) -> some View {
        let color: Color = text == "Free" ? .green : (text == "Smart" ? Theme.purple : .blue)
        return Text(text).font(.caption2)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.2)).foregroundStyle(color)
            .clipShape(Capsule())
    }
}
