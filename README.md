# KENIOS — App chat đa-AI (iOS 16+)

App iOS kết nối tới backend `codebox.py` (chạy trên VPS/hosting của bạn).
Repo này build ra **IPA chưa ký (unsigned)** tự động bằng GitHub Actions — **không cần máy Mac**.

## Tính năng
- Đăng nhập / đăng ký / quên mật khẩu / đổi Gmail–SĐT–mật khẩu
- Nhiều AI (model mới nhất 2025): OpenAI GPT-4o, Claude (Opus/Sonnet/Haiku 4.5), Gemini 2.0,
  Groq, OpenRouter, Mistral, DeepSeek R1, Grok 3, Perplexity, Together, Fireworks, Cerebras,
  Moonshot, Qwen, NVIDIA NIM, Cohere
- Nhập API key ngay trên app (mã hóa khi lưu ở máy chủ) — **không nhúng key trong app**
- Chế độ **Đối xứng (ensemble)**: chọn ≥2 AI → 1 AI tổng hợp ra câu trả lời tốt nhất
- Nút **+** đính ảnh (thư viện) hoặc **Tệp/Drive** — hỗ trợ ảnh, PDF, văn bản, code (file_base64)
- Giọng nói → văn bản (micro, Whisper)
- Tab **Lập trình**: chạy code Python trực tiếp trên server (sandbox), và công cụ AI lập trình
  (review / debug / explain / convert / test / optimize / document / security)
- Thư viện file: chạy thử file `.py` / `.js` / `.sh` đã tải lên, xem kết quả stdout/stderr
- **Credits & nâng cấp Pro**: xem số dư credits, chọn gói nạp, xem thông tin chuyển khoản,
  lịch sử giao dịch
- Lưu lịch sử hội thoại; lưu/chia sẻ câu trả lời về máy
- Cài đặt tách **VPS / Hosting** — chỉ cần nhập IP/URL
- Token đăng nhập lưu trong Keychain (iOS mã hóa)

## Cách tạo IPA trên GitHub (các bước)
1. Tạo repo mới trên GitHub (vd `kenios-app`).
2. Đẩy toàn bộ thư mục này lên nhánh `main`:
   ```bash
   git init
   git add .
   git commit -m "KENIOS app"
   git branch -M main
   git remote add origin https://github.com/<tên-bạn>/kenios-app.git
   git push -u origin main
   ```
3. Vào tab **Actions** → workflow **Build unsigned IPA** sẽ tự chạy
   (hoặc bấm **Run workflow**).
4. Khi xong, mở lần chạy → mục **Artifacts** → tải `KENIOS-unsigned-ipa`
   → bên trong là `KENIOS-unsigned.ipa`.

## Cài lên iPhone (IPA chưa ký)
IPA chưa ký nên cần công cụ sideload:
- **AltStore / SideStore**, **Sideloadly**, hoặc chứng chỉ nhà phát triển của bạn.
- (App Store yêu cầu ký bằng tài khoản Apple Developer — đó là bước riêng.)

## Sau khi mở app
1. Nhập **IP/URL VPS** (vd `http://1.2.3.4:8000`) → Kiểm tra & Lưu.
2. Đăng ký / đăng nhập.
3. Vào **Chọn AI / Nhập API key** → dán key (ưu tiên AI nhãn *free*: Gemini, Groq, OpenRouter).
4. Chat.

## Backend
Chạy `codebox.py` trên VPS trước (xem hướng dẫn trong file đó). App chỉ là client.

## Cấu trúc
```
project.yml                 # cấu hình XcodeGen (sinh ra .xcodeproj khi build)
.github/workflows/build-ipa.yml
Sources/
  KENIOSApp.swift           # entry
  AppStore.swift            # trạng thái app
  APIClient.swift           # gọi backend
  Models.swift              # kiểu dữ liệu
  Keychain.swift            # lưu token mã hóa
  VoiceRecorder.swift       # thu âm
  Views/                    # các màn hình (Chat, Lập trình, Thư viện, Cài đặt, Nạp credits, Quản trị...)
```

> Lưu ý: `KENIOS.xcodeproj` KHÔNG commit — nó được XcodeGen sinh ra lúc build.
> Muốn mở bằng Xcode trên máy Mac: cài `brew install xcodegen` rồi chạy `xcodegen generate`.

---

## Cập nhật mới

### Quản trị viên (Admin)
- Backend tự tạo tài khoản admin khi khởi động: **kenios / admin1999@**
  (đổi qua biến môi trường `ADMIN_USER`, `ADMIN_PASS`; nên đổi mật khẩu ngay sau khi đăng nhập).
- Đăng nhập bằng tài khoản admin → app hiện tab **Quản trị**: xem danh sách người dùng + credits,
  khóa/mở tài khoản, đổi mật khẩu giúp người dùng, đặt gói Free/Pro, xác nhận đơn nạp credits
  (nhập ID đơn thanh toán → "Xác nhận").

### Backend codebox.py v3.0
- App này dùng đúng API của `backend/codebox.py` bản v3.0: model AI mới nhất, sửa lỗi 404 Gemini,
  đính kèm ảnh/file đầy đủ (`image` hoặc `file_base64` + `file_mime`), endpoint `/run/python`,
  `/run/test`, `/code/ai`, và `/payment/*`.
- `/run/python` chạy code trực tiếp trên VPS trong `subprocess` có giới hạn thời gian
  (`SANDBOX_TIMEOUT`, mặc định 15s). Đây là tính năng **thực thi code trên server** — chỉ bật
  cho người dùng tin cậy, vì có rủi ro nếu server không được cấu hình cách ly (container/jail).
- Thanh toán/nạp credits hiện theo hình thức chuyển khoản thủ công + admin xác nhận
  (`/payment/create`, `/payment/confirm/{id}`). Có thể tích hợp Stripe qua biến môi trường
  `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` nếu mở rộng thêm.

### Kết nối VPS/Hosting riêng của từng khách
- Mỗi người tự thêm **máy chủ riêng** (VPS hoặc Hosting) trong Cài đặt → "Quản lý máy chủ".
- Lưu nhiều hồ sơ, chọn cái đang dùng; chỉ cần nhập IP/URL là kết nối.

### Hiệu ứng iOS 26 (Liquid Glass)
- App dùng `glassEffect` của iOS 26 cho các điều khiển (có fallback material cho iOS 16–25).
- Khi build bằng **Xcode 26** (SDK iOS 26), thanh công cụ/tab/sheet/nút gốc tự động lên giao diện Liquid Glass.
- Workflow GitHub Actions đã đặt dùng Xcode mới nhất (`latest-stable`). Nếu runner chưa có Xcode 26,
  build vẫn chạy nhưng hiệu ứng glass tùy biến sẽ cần Xcode 26 để biên dịch.

> Về "nâng gói Pro của AI": app chỉ quản lý **gói Pro nội bộ của KENIOS** (admin cấp).
> App không mở khóa gói trả phí của các nhà cung cấp AI — hãy dùng API key của bạn
> (ưu tiên các nhà cung cấp có gói free hợp lệ).
