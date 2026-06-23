import Foundation
import CryptoKit

// Mã hóa / giải mã dữ liệu người dùng lưu cục bộ (AES-GCM).
// Khóa lưu trong Keychain, sinh ngẫu nhiên lần đầu.
enum LocalCrypto {
    private static var key: SymmetricKey {
        if let s = Keychain.load("enc_key"), let data = Data(base64Encoded: s) {
            return SymmetricKey(data: data)
        }
        let k = SymmetricKey(size: .bits256)
        let raw = k.withUnsafeBytes { Data($0) }
        Keychain.save("enc_key", raw.base64EncodedString())
        return k
    }

    static func encrypt(_ text: String) -> String? {
        guard let sealed = try? AES.GCM.seal(Data(text.utf8), using: key),
              let combined = sealed.combined else { return nil }
        return combined.base64EncodedString()
    }

    static func decrypt(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let out = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: out, encoding: .utf8)
    }
}
