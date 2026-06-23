import SwiftUI

// Hiệu ứng Liquid Glass của iOS 26. Trên iOS cũ hơn tự động dùng material.
// Lưu ý: cần build bằng Xcode 26 (SDK iOS 26) để biên dịch glassEffect.
extension View {
    @ViewBuilder
    func kGlass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func kGlassInteractive<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                self.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
