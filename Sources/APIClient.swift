import Foundation

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

struct APIClient {
    let baseURL: String
    var token: String?

    private var root: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func makeURL(_ path: String) throws -> URL {
        guard let u = URL(string: root + path) else {
            throw APIError.message("URL máy chủ không hợp lệ.")
        }
        return u
    }

    private func send(_ path: String, method: String = "GET",
                      json: [String: Any]? = nil, auth: Bool = true) async throws -> Data {
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = method
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.message("Không kết nối được máy chủ. Kiểm tra IP/URL & mạng.")
        }
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.message("Phản hồi không hợp lệ.")
        }
        if !(200..<300).contains(http.statusCode) {
            var detail = "Lỗi máy chủ (\(http.statusCode))."
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = obj["detail"] as? String { detail = d }
            throw APIError.message(detail)
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    // ---- Hệ thống ----
    func getConfig() async throws -> ServerConfig {
        try decode(try await send("/config", auth: false))
    }
    func getProviders() async throws -> [Provider] {
        try decode(try await send("/providers", auth: false))
    }

    // ---- Tài khoản ----
    func register(_ username: String, _ password: String, email: String?, phone: String?) async throws -> AuthResponse {
        var body: [String: Any] = ["username": username, "password": password]
        if let email, !email.isEmpty { body["email"] = email }
        if let phone, !phone.isEmpty { body["phone"] = phone }
        return try decode(try await send("/auth/register", method: "POST", json: body, auth: false))
    }
    func login(_ username: String, _ password: String) async throws -> AuthResponse {
        try decode(try await send("/auth/login", method: "POST",
                                  json: ["username": username, "password": password], auth: false))
    }
    func forgot(_ username: String) async throws -> ForgotResponse {
        try decode(try await send("/auth/forgot-password", method: "POST",
                                  json: ["username": username], auth: false))
    }
    func reset(_ token: String, _ newPassword: String) async throws -> MessageResponse {
        try decode(try await send("/auth/reset-password", method: "POST",
                                  json: ["token": token, "new_password": newPassword], auth: false))
    }
    func updateProfile(email: String?, phone: String?, newPassword: String?) async throws -> MessageResponse {
        var body: [String: Any] = [:]
        if let email { body["email"] = email }
        if let phone { body["phone"] = phone }
        if let newPassword, !newPassword.isEmpty { body["new_password"] = newPassword }
        return try decode(try await send("/auth/update-profile", method: "POST", json: body))
    }

    // ---- API key ----
    func saveKey(provider: String, apiKey: String) async throws -> MessageResponse {
        try decode(try await send("/keys", method: "POST",
                                  json: ["provider": provider, "api_key": apiKey]))
    }
    func listKeys() async throws -> [KeyInfo] {
        try decode(try await send("/keys"))
    }
    func deleteKey(provider: String) async throws -> MessageResponse {
        try decode(try await send("/keys/\(provider)", method: "DELETE"))
    }
    func testKey(provider: String, apiKey: String) async throws -> MessageResponse {
        try decode(try await send("/keys/test", method: "POST",
                                  json: ["provider": provider, "api_key": apiKey]))
    }

    // ---- Chat ----
    func chat(provider: String, message: String, image: String?,
              fileBase64: String? = nil, fileMime: String? = nil,
              model: String?, conversationId: Int?, system: String? = nil) async throws -> ChatResponse {
        var body: [String: Any] = ["provider": provider, "message": message]
        if let image { body["image"] = image }
        if let fileBase64 { body["file_base64"] = fileBase64 }
        if let fileMime { body["file_mime"] = fileMime }
        if let model { body["model"] = model }
        if let conversationId { body["conversation_id"] = conversationId }
        if let system { body["system"] = system }
        return try decode(try await send("/chat", method: "POST", json: body))
    }
    func ensemble(providers: [String], message: String, judge: String?) async throws -> EnsembleResponse {
        var body: [String: Any] = ["providers": providers, "message": message]
        if let judge { body["judge"] = judge }
        return try decode(try await send("/chat/ensemble", method: "POST", json: body))
    }

    // ---- Lịch sử ----
    func conversations() async throws -> [Conversation] {
        try decode(try await send("/conversations"))
    }
    func conversation(_ id: Int) async throws -> ConversationDetail {
        try decode(try await send("/conversations/\(id)"))
    }
    func deleteConversation(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/conversations/\(id)", method: "DELETE"))
    }

    // ---- Admin ----
    func adminUsers() async throws -> [AdminUser] {
        try decode(try await send("/admin/users"))
    }
    func adminBan(_ uid: Int, banned: Bool) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/ban", method: "POST", json: ["banned": banned]))
    }
    func adminSetPassword(_ uid: Int, newPassword: String) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/password", method: "POST",
                                  json: ["new_password": newPassword]))
    }
    func adminSetPlan(_ uid: Int, plan: String) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/plan", method: "POST", json: ["plan": plan]))
    }
    func adminConfirmPayment(_ pid: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/payments/\(pid)/confirm", method: "POST"))
    }
    func adminErrors() async throws -> [ErrorLog] {
        try decode(try await send("/admin/errors"))
    }
    func adminClearErrors() async throws -> MessageResponse {
        try decode(try await send("/admin/errors", method: "DELETE"))
    }
    func adminGetBank() async throws -> BankSettings {
        try decode(try await send("/admin/payment/settings"))
    }
    func adminSetBank(_ s: BankSettings) async throws -> MessageResponse {
        try decode(try await send("/admin/payment/settings", method: "POST", json: [
            "bank_code": s.bankCode, "bank_short": s.bankShort,
            "bank_account": s.bankAccount, "bank_name": s.bankName,
            "bank_webhook": s.bankWebhook, "bank_apikey": s.bankApikey
        ]))
    }

    // ---- File ----
    func listFiles(category: String?) async throws -> [FileItem] {
        var path = "/files"
        if let category, category != "all" { path += "?category=\(category)" }
        return try decode(try await send(path))
    }
    func uploadFile(name: String, category: String, dataBase64: String) async throws -> UploadResponse {
        try decode(try await send("/files", method: "POST",
                                  json: ["name": name, "category": category, "data_base64": dataBase64]))
    }
    func downloadFile(_ id: Int) async throws -> FileDetail {
        try decode(try await send("/files/\(id)"))
    }
    func deleteFile(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/files/\(id)", method: "DELETE"))
    }

    // ---- Giọng nói ----
    func transcribe(provider: String, audioBase64: String, mime: String) async throws -> VoiceResponse {
        try decode(try await send("/voice/transcribe", method: "POST",
                                  json: ["provider": provider, "audio_base64": audioBase64, "mime": mime]))
    }

    // ---- Chạy code / Sandbox ----
    func runPython(code: String, stdin: String? = nil) async throws -> CodeRunResult {
        var body: [String: Any] = ["code": code]
        if let stdin { body["stdin"] = stdin }
        return try decode(try await send("/run/python", method: "POST", json: body))
    }
    func runCode(language: String, code: String, stdin: String? = nil) async throws -> CodeRunResult {
        var body: [String: Any] = ["code": code, "language": language]
        if let stdin { body["stdin"] = stdin }
        return try decode(try await send("/run/code", method: "POST", json: body))
    }
    func runTestFile(fileId: Int, args: String? = nil) async throws -> FileRunResult {
        var body: [String: Any] = ["file_id": fileId]
        if let args { body["args"] = args }
        return try decode(try await send("/run/test", method: "POST", json: body))
    }

    // ---- AI lập trình (review/debug/explain/convert/test/optimize/document/security) ----
    func codeAI(provider: String, code: String, language: String?, task: String,
                targetLang: String? = nil, model: String? = nil) async throws -> CodeAIResult {
        var body: [String: Any] = ["provider": provider, "code": code, "task": task]
        if let language { body["language"] = language }
        if let targetLang { body["target_lang"] = targetLang }
        if let model { body["model"] = model }
        return try decode(try await send("/code/ai", method: "POST", json: body))
    }

    // ---- Credits & Thanh toán ----
    func myCredits() async throws -> CreditsResponse {
        try decode(try await send("/me/credits"))
    }
    func paymentPackages() async throws -> [PaymentPackage] {
        try decode(try await send("/payment/packages", auth: false))
    }
    func createPayment(package: String, amount: Int) async throws -> PaymentCreateResponse {
        try decode(try await send("/payment/create", method: "POST",
                                  json: ["package": package, "amount": amount]))
    }
    func paymentHistory() async throws -> [PaymentRecord] {
        try decode(try await send("/payment/history"))
    }
}
