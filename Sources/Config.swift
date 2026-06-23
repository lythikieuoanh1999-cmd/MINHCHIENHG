import Foundation

enum Config {
    // 👉 ĐIỀN URL VPS CỦA BẠN VÀO ĐÂY (máy chủ đang chạy codebox.py).
    //    Khi có giá trị này, mở app là đăng nhập luôn — KHÔNG cần bước liên kết.
    //    Để TRỐNG ("") nếu muốn bắt người dùng tự nhập máy chủ khi mở app.
    //    Ví dụ: "https://api.kenios.com"  hoặc  "http://123.45.67.89:8000"
    static let defaultServerURL = ""

    static let defaultServerType = "VPS"
}
