"""
codebox.py — Backend đa-AI cho app KENIOS (com.kenios.codebox)  v3.0
======================================================================
TÍNH NĂNG MỚI / SỬA LỖI (v3.0):
  ✅ Gemini: cập nhật model mới nhất (gemini-2.0-flash, gemini-1.5-pro v002...)
             sửa lỗi 404 "model not found" — dùng đúng API v1beta
  ✅ Đính ảnh (image_base64) VÀ đính file (file_base64 + mime) hoạt động đầy đủ
  ✅ Chọn ngôn ngữ giao diện trả về (vi / en / auto)
  ✅ Giọng nói: phiên âm qua Whisper (OpenAI) hoặc Gemini Speech-to-Text
  ✅ Chạy code trực tiếp trên server (sandbox Python) — /run/python
  ✅ Chạy test file (.py / .js / .sh) và trả kết quả — /run/test
  ✅ Mô hình mới nhất cho mỗi nhà cung cấp (GPT-4o, Claude 3.7, Gemini 2.0 Flash…)
  ✅ Nhiều tính năng lập trình: code review, debug, explain, convert ngôn ngữ
  ✅ Thanh toán / nạp credits (Stripe webhook) — /payment/*
  ✅ Ensemble AI (hỏi nhiều AI song song, tổng hợp)
  ✅ Lỗi rõ ràng: 401/403/404/429 đều có thông báo tiếng Việt cụ thể

------------------------------------------------------------------
CÀI ĐẶT (Ubuntu/Debian):
    sudo apt update && sudo apt install -y python3-venv python3-dev
    python3 -m venv venv && source venv/bin/activate
    pip install "fastapi>=0.110" "uvicorn[standard]>=0.29" \
                "httpx>=0.27" "cryptography>=42" "stripe>=8.0" \
                "python-multipart>=0.0.9"

CHẠY:
    export CODEBOX_SECRET="chuoi-bi-mat-dai-ngau-nhien"
    export STRIPE_SECRET_KEY="sk_live_..."        # nếu dùng thanh toán
    export STRIPE_WEBHOOK_SECRET="whsec_..."      # nếu dùng Stripe webhook
    python codebox.py

CHẠY 24/7 (systemd) — xem hướng dẫn cuối file.
NÊN đặt sau Nginx + HTTPS (Let's Encrypt).
------------------------------------------------------------------
"""

import os, re, time, json, hmac, base64, hashlib, secrets
import sqlite3, logging, asyncio, subprocess, tempfile, sys, shutil
from typing import Any, Optional

import httpx
from fastapi import FastAPI, Request, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# ========================= Cấu hình =========================
DB_PATH         = os.getenv("CODEBOX_DB", "codebox.db")
PORT            = int(os.getenv("PORT", "8000"))
SECRET          = os.getenv("CODEBOX_SECRET") or secrets.token_hex(32)
TOKEN_TTL       = int(os.getenv("TOKEN_TTL", str(60 * 60 * 24 * 30)))  # 30 ngày
REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT", "120"))
SANDBOX_TIMEOUT = int(os.getenv("SANDBOX_TIMEOUT", "15"))  # giây chạy code
STRIPE_SECRET   = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_WH_SEC   = os.getenv("STRIPE_WEBHOOK_SECRET", "")

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("codebox")

# ----- Fernet (mã hóa API key) -----
from cryptography.fernet import Fernet
_key_file = os.getenv("CODEBOX_ENC_KEYFILE", "codebox_enc.key")
if os.getenv("CODEBOX_ENC_KEY"):
    _enc_key = os.getenv("CODEBOX_ENC_KEY").encode()
elif os.path.exists(_key_file):
    _enc_key = open(_key_file, "rb").read().strip()
else:
    _enc_key = Fernet.generate_key()
    with open(_key_file, "wb") as f: f.write(_enc_key)
    log.info("Tạo khóa mã hóa mới: %s", _key_file)
fernet = Fernet(_enc_key)

def enc(text: str) -> str: return fernet.encrypt(text.encode()).decode()
def dec(token: str) -> str: return fernet.decrypt(token.encode()).decode()


# ===================== Danh sách AI (models mới nhất 2025) =====================
PROVIDERS: dict[str, dict[str, Any]] = {
    "openai": {
        "label": "OpenAI · GPT-4o",
        "kind": "openai",
        "base": "https://api.openai.com/v1",
        "default_model": "gpt-4o",
        "models": ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1", "o3-mini"],
        "vision": True, "free": False,
        "code": True,
    },
    "anthropic": {
        "label": "Anthropic · Claude 3.7",
        "kind": "anthropic",
        "base": "https://api.anthropic.com/v1",
        "default_model": "claude-sonnet-4-5",
        "models": [
            "claude-opus-4-5",
            "claude-sonnet-4-5",
            "claude-haiku-4-5",
            "claude-3-5-sonnet-latest",
            "claude-3-5-haiku-latest",
        ],
        "vision": True, "free": False,
        "code": True,
    },
    "gemini": {
        "label": "Google · Gemini 2.0",
        "kind": "gemini",
        # v1beta — chuẩn cho generateContent
        "base": "https://generativelanguage.googleapis.com/v1beta",
        "default_model": "gemini-2.0-flash",
        "models": [
            "gemini-2.0-flash",
            "gemini-2.0-flash-lite",
            "gemini-1.5-pro-002",
            "gemini-1.5-flash-002",
            "gemini-1.5-flash-8b",
        ],
        "vision": True, "free": True,
        "code": True,
    },
    "groq": {
        "label": "Groq · Llama 3.3 (free)",
        "kind": "openai",
        "base": "https://api.groq.com/openai/v1",
        "default_model": "llama-3.3-70b-versatile",
        "models": [
            "llama-3.3-70b-versatile",
            "llama-3.1-8b-instant",
            "mixtral-8x7b-32768",
            "deepseek-r1-distill-llama-70b",
        ],
        "vision": False, "free": True,
        "code": True,
    },
    "openrouter": {
        "label": "OpenRouter (nhiều model, có free)",
        "kind": "openai",
        "base": "https://openrouter.ai/api/v1",
        "default_model": "google/gemini-2.0-flash-exp:free",
        "models": [
            "google/gemini-2.0-flash-exp:free",
            "meta-llama/llama-3.3-70b-instruct:free",
            "deepseek/deepseek-r1:free",
            "qwen/qwen-2.5-72b-instruct",
            "anthropic/claude-3.5-sonnet",
        ],
        "vision": True, "free": True,
        "code": True,
    },
    "mistral": {
        "label": "Mistral",
        "kind": "openai",
        "base": "https://api.mistral.ai/v1",
        "default_model": "mistral-large-latest",
        "models": ["mistral-large-latest", "mistral-small-latest", "codestral-latest"],
        "vision": False, "free": False,
        "code": True,
    },
    "deepseek": {
        "label": "DeepSeek R1",
        "kind": "openai",
        "base": "https://api.deepseek.com/v1",
        "default_model": "deepseek-chat",
        "models": ["deepseek-chat", "deepseek-reasoner"],
        "vision": False, "free": False,
        "code": True,
    },
    "xai": {
        "label": "xAI · Grok 3",
        "kind": "openai",
        "base": "https://api.x.ai/v1",
        "default_model": "grok-3-latest",
        "models": ["grok-3-latest", "grok-3-mini-latest", "grok-2-vision-latest"],
        "vision": True, "free": False,
        "code": True,
    },
    "perplexity": {
        "label": "Perplexity · Sonar Pro",
        "kind": "openai",
        "base": "https://api.perplexity.ai",
        "default_model": "sonar-pro",
        "models": ["sonar-pro", "sonar", "sonar-reasoning-pro"],
        "vision": False, "free": False,
        "code": False,
    },
    "together": {
        "label": "Together AI",
        "kind": "openai",
        "base": "https://api.together.xyz/v1",
        "default_model": "meta-llama/Llama-3.3-70B-Instruct-Turbo",
        "models": [
            "meta-llama/Llama-3.3-70B-Instruct-Turbo",
            "Qwen/Qwen2.5-72B-Instruct-Turbo",
            "deepseek-ai/DeepSeek-R1",
        ],
        "vision": False, "free": False,
        "code": True,
    },
    "fireworks": {
        "label": "Fireworks AI",
        "kind": "openai",
        "base": "https://api.fireworks.ai/inference/v1",
        "default_model": "accounts/fireworks/models/llama-v3p3-70b-instruct",
        "models": ["accounts/fireworks/models/llama-v3p3-70b-instruct",
                   "accounts/fireworks/models/deepseek-r1"],
        "vision": False, "free": False,
        "code": True,
    },
    "cerebras": {
        "label": "Cerebras (siêu nhanh, free)",
        "kind": "openai",
        "base": "https://api.cerebras.ai/v1",
        "default_model": "llama-3.3-70b",
        "models": ["llama-3.3-70b", "llama-3.1-8b"],
        "vision": False, "free": True,
        "code": True,
    },
    "moonshot": {
        "label": "Moonshot · Kimi",
        "kind": "openai",
        "base": "https://api.moonshot.ai/v1",
        "default_model": "moonshot-v1-32k",
        "models": ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"],
        "vision": False, "free": False,
        "code": True,
    },
    "qwen": {
        "label": "Alibaba · Qwen 2.5",
        "kind": "openai",
        "base": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        "default_model": "qwen-max",
        "models": ["qwen-max", "qwen-plus", "qwen-turbo", "qwen-coder-plus"],
        "vision": False, "free": False,
        "code": True,
    },
    "nvidia": {
        "label": "NVIDIA NIM (free)",
        "kind": "openai",
        "base": "https://integrate.api.nvidia.com/v1",
        "default_model": "meta/llama-3.3-70b-instruct",
        "models": ["meta/llama-3.3-70b-instruct", "nvidia/llama-3.1-nemotron-70b-instruct"],
        "vision": False, "free": True,
        "code": True,
    },
    "cohere": {
        "label": "Cohere · Command R+",
        "kind": "openai",
        "base": "https://api.cohere.ai/compatibility/v1",
        "default_model": "command-r-plus-08-2024",
        "models": ["command-r-plus-08-2024", "command-r-08-2024"],
        "vision": False, "free": False,
        "code": False,
    },
}

DEFAULT_SYSTEM = os.getenv(
    "SYSTEM_PROMPT",
    "Bạn là trợ lý AI của ứng dụng KENIOS. Trả lời hữu ích, chính xác. "
    "Khi viết code, luôn kèm theo giải thích rõ ràng. "
    "Hỗ trợ: Python, JavaScript, TypeScript, Swift, Kotlin, Go, Rust, C/C++, "
    "Java, PHP, HTML/CSS, SQL, Shell script. "
    "Ưu tiên dùng tiếng Việt trừ khi người dùng yêu cầu khác.",
)

# ========================== Cơ sở dữ liệu ==========================
def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db() -> None:
    with db() as c:
        c.executescript("""
            CREATE TABLE IF NOT EXISTS users(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT,
                phone TEXT,
                pw_hash TEXT NOT NULL,
                reset_token TEXT,
                reset_exp INTEGER,
                is_admin INTEGER DEFAULT 0,
                banned INTEGER DEFAULT 0,
                plan TEXT DEFAULT 'free',
                credits INTEGER DEFAULT 0,
                lang TEXT DEFAULT 'vi',
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS apikeys(
                user_id INTEGER NOT NULL,
                provider TEXT NOT NULL,
                enc_key TEXT NOT NULL,
                PRIMARY KEY(user_id, provider)
            );
            CREATE TABLE IF NOT EXISTS conversations(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                title TEXT,
                provider TEXT,
                created_at INTEGER,
                updated_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS messages(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id INTEGER NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS files(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                category TEXT,
                mime TEXT,
                size INTEGER,
                data TEXT NOT NULL,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS payments(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                amount INTEGER NOT NULL,
                credits INTEGER NOT NULL,
                status TEXT DEFAULT 'pending',
                ref TEXT,
                created_at INTEGER
            );
            CREATE TABLE IF NOT EXISTS settings(
                key TEXT PRIMARY KEY,
                value TEXT
            );
            CREATE TABLE IF NOT EXISTS error_logs(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                username TEXT,
                context TEXT,
                detail TEXT,
                created_at INTEGER
            );
        """)
    # Migration an toàn cho DB cũ
    _migrate(c)

    # Seed admin
    admin_user = os.getenv("ADMIN_USER", "kenios")
    admin_pass = os.getenv("ADMIN_PASS", "admin1999@")
    with db() as c:
        row = c.execute("SELECT id FROM users WHERE username=?", (admin_user,)).fetchone()
        if row:
            c.execute("UPDATE users SET is_admin=1, banned=0 WHERE id=?", (row["id"],))
        else:
            c.execute(
                "INSERT INTO users(username,pw_hash,is_admin,plan,credits,created_at) VALUES(?,?,1,'pro',9999,?)",
                (admin_user, hash_pw(admin_pass), int(time.time())),
            )
            log.info("Tạo admin '%s' (hãy đổi mật khẩu sau khi đăng nhập!)", admin_user)
    # Seed cấu hình ngân hàng mặc định (admin sửa được trong app)
    _seed_setting("bank_code", os.getenv("BANK_CODE", "970416"))        # ACB
    _seed_setting("bank_short", os.getenv("BANK_SHORT", "ACB"))
    _seed_setting("bank_account", os.getenv("BANK_ACCOUNT", "23252921"))
    _seed_setting("bank_name", os.getenv("BANK_NAME", "TRAN MINH CHIEN"))
    _seed_setting("bank_webhook", "")
    _seed_setting("bank_apikey", "")
    log.info("DB sẵn sàng: %s", DB_PATH)


def get_setting(key: str, default: str = "") -> str:
    with db() as c:
        row = c.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return row["value"] if row else default


def set_setting(key: str, value: str) -> None:
    with db() as c:
        c.execute("INSERT INTO settings(key,value) VALUES(?,?) "
                  "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))


def _seed_setting(key: str, value: str) -> None:
    with db() as c:
        if not c.execute("SELECT 1 FROM settings WHERE key=?", (key,)).fetchone():
            c.execute("INSERT INTO settings(key,value) VALUES(?,?)", (key, value))


def _migrate(conn: sqlite3.Connection) -> None:
    """Thêm cột mới vào bảng cũ nếu chưa có."""
    migrations = [
        ("users", "is_admin", "INTEGER DEFAULT 0"),
        ("users", "banned",   "INTEGER DEFAULT 0"),
        ("users", "plan",     "TEXT DEFAULT 'free'"),
        ("users", "credits",  "INTEGER DEFAULT 0"),
        ("users", "lang",     "TEXT DEFAULT 'vi'"),
        ("files", "mime",     "TEXT"),
    ]
    with db() as c:
        for table, col, ddl in migrations:
            try:
                c.execute(f"ALTER TABLE {table} ADD COLUMN {col} {ddl}")
            except Exception:
                pass


# ========================== Bảo mật ==========================
def hash_pw(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 200_000)
    return salt.hex() + "$" + dk.hex()


def verify_pw(password: str, stored: str) -> bool:
    try:
        salt_hex, dk_hex = stored.split("$", 1)
        dk = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), 200_000)
        return hmac.compare_digest(dk.hex(), dk_hex)
    except Exception:
        return False


def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def _b64u_dec(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def make_token(user_id: int) -> str:
    payload = {"uid": user_id, "exp": int(time.time()) + TOKEN_TTL}
    body = _b64u(json.dumps(payload, separators=(",", ":")).encode())
    sig = _b64u(hmac.new(SECRET.encode(), body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def verify_token(token: str) -> int:
    try:
        body, sig = token.split(".", 1)
        good = _b64u(hmac.new(SECRET.encode(), body.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, good):
            raise ValueError("sai chữ ký")
        payload = json.loads(_b64u_dec(body))
        if payload["exp"] < time.time():
            raise ValueError("hết hạn")
        return int(payload["uid"])
    except Exception:
        raise HTTPException(status_code=401, detail="Phiên đăng nhập không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.")


def get_user(authorization: Optional[str] = Header(default=None)) -> sqlite3.Row:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Thiếu token đăng nhập.")
    uid = verify_token(authorization.split(" ", 1)[1])
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="Tài khoản không tồn tại.")
    if row["banned"]:
        raise HTTPException(status_code=403, detail="Tài khoản đã bị khóa. Liên hệ quản trị viên.")
    return row


def get_admin(user=Depends(get_user)) -> sqlite3.Row:
    if not user["is_admin"]:
        raise HTTPException(status_code=403, detail="Chỉ quản trị viên mới được phép.")
    return user


# ===================== Xử lý ảnh & file =====================
def parse_image(image: str) -> tuple[str, str]:
    """Trả về (media_type, base64_thuần)."""
    if image.startswith("data:"):
        head, data = image.split(",", 1)
        m = re.search(r"data:(.*?);base64", head)
        return (m.group(1) if m else "image/jpeg"), data
    return "image/jpeg", image


# ===================== Lỗi nhà cung cấp =====================
def _raise_for_provider(r: httpx.Response, provider: str) -> None:
    if r.status_code < 400:
        return
    txt = r.text[:500]
    if r.status_code in (401, 403):
        raise HTTPException(status_code=400,
            detail=f"{provider}: API key sai hoặc không đủ quyền ({r.status_code}). "
                   f"Vui lòng kiểm tra lại API key trong phần Cài đặt. Chi tiết: {txt}")
    if r.status_code == 404:
        raise HTTPException(status_code=400,
            detail=f"{provider}: Model không tồn tại hoặc chưa được hỗ trợ (404). "
                   f"Vui lòng chọn model khác. Chi tiết: {txt}")
    if r.status_code == 429:
        raise HTTPException(status_code=429,
            detail=f"{provider}: Vượt quá giới hạn tốc độ (429). "
                   f"Vui lòng đợi vài giây rồi thử lại.")
    raise HTTPException(status_code=502,
        detail=f"{provider} lỗi {r.status_code}: {txt}")


def get_user_key(user_id: int, provider: str, inline: Optional[str]) -> str:
    if inline:
        return inline
    with db() as c:
        row = c.execute("SELECT enc_key FROM apikeys WHERE user_id=? AND provider=?",
                        (user_id, provider)).fetchone()
    if not row:
        raise HTTPException(status_code=400,
            detail=f"Chưa có API key cho '{provider}'. Hãy vào Cài đặt → API Keys để nhập key.")
    return dec(row["enc_key"])


def save_code_blocks(user_id: int, text: str, label: str = "code") -> list[dict[str, Any]]:
    """Tự động trích code trong câu trả lời AI và lưu thành file (giống Claude)."""
    safe = re.sub(r"[^a-zA-Z0-9_]+", "", label) or "code"
    ext_map = {"python": "py", "py": "py", "javascript": "js", "js": "js",
               "typescript": "ts", "ts": "ts", "html": "html", "css": "css",
               "json": "json", "bash": "sh", "sh": "sh", "swift": "swift",
               "java": "java", "c": "c", "cpp": "cpp", "go": "go", "rust": "rs",
               "sql": "sql", "yaml": "yml", "yml": "yml", "markdown": "md", "md": "md",
               "php": "php", "ruby": "rb", "kotlin": "kt", "dart": "dart"}
    blocks = re.findall(r"```([a-zA-Z0-9_+\-]*)\n(.*?)```", text, re.DOTALL)
    saved: list[dict[str, Any]] = []
    n = 0
    for lang, code in blocks:
        code = code.rstrip("\n")
        if len(code.strip()) < 10:
            continue
        n += 1
        ext = ext_map.get(lang.lower().strip(), "txt")
        name = f"{safe}_{n}.{ext}"
        data_b64 = base64.b64encode(code.encode("utf-8")).decode()
        try:
            with db() as c:
                cur = c.execute(
                    "INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
                    "VALUES(?,?,?,?,?,?,?)",
                    (user_id, name, "code", "text/plain", len(code), data_b64, int(time.time())))
                saved.append({"id": cur.lastrowid, "name": name})
        except Exception:
            pass
    return saved


# ===================== Gọi AI =====================
async def call_provider(
    provider: str,
    api_key: str,
    model: Optional[str],
    history: list[dict[str, Any]],
    user_text: str,
    image: Optional[str] = None,
    file_b64: Optional[str] = None,
    file_mime: Optional[str] = None,
    system_override: Optional[str] = None,
) -> str:
    if provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"AI '{provider}' không được hỗ trợ.")
    p    = PROVIDERS[provider]
    model = model or p["default_model"]
    kind  = p["kind"]
    sys_msg = system_override or DEFAULT_SYSTEM

    # Ưu tiên image, nếu không có thì dùng file_b64 (nếu là ảnh)
    img = None
    if image:
        img = parse_image(image)
    elif file_b64 and file_mime and file_mime.startswith("image/"):
        img = (file_mime, file_b64)

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        # -------- OpenAI-compatible --------
        if kind == "openai":
            msgs = [{"role": "system", "content": sys_msg}]
            msgs += [{"role": m["role"], "content": m["content"]} for m in history]
            if img:
                media, data = img
                user_content: Any = [
                    {"type": "text", "text": user_text or ""},
                    {"type": "image_url", "image_url": {"url": f"data:{media};base64,{data}"}},
                ]
            elif file_b64 and file_mime:
                # file không phải ảnh → gửi nội dung dạng text nếu là text/code
                try:
                    decoded = base64.b64decode(file_b64).decode("utf-8", errors="replace")
                    user_content = f"{user_text}\n\n[Nội dung file]\n```\n{decoded[:8000]}\n```"
                except Exception:
                    user_content = user_text or ""
            else:
                user_content = user_text
            msgs.append({"role": "user", "content": user_content})
            r = await client.post(
                f"{p['base']}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}",
                         "HTTP-Referer": "https://kenios.app",
                         "X-Title": "KENIOS"},
                json={"model": model, "messages": msgs},
            )
            _raise_for_provider(r, provider)
            return r.json()["choices"][0]["message"]["content"]

        # -------- Anthropic --------
        if kind == "anthropic":
            msgs = [{"role": m["role"], "content": m["content"]} for m in history]
            if img:
                media, data = img
                msgs.append({"role": "user", "content": [
                    {"type": "text", "text": user_text or ""},
                    {"type": "image", "source": {"type": "base64",
                                                  "media_type": media, "data": data}},
                ]})
            elif file_b64 and file_mime:
                if file_mime == "application/pdf":
                    msgs.append({"role": "user", "content": [
                        {"type": "text", "text": user_text or ""},
                        {"type": "document", "source": {"type": "base64",
                                                         "media_type": "application/pdf",
                                                         "data": file_b64}},
                    ]})
                else:
                    try:
                        decoded = base64.b64decode(file_b64).decode("utf-8", errors="replace")
                        msgs.append({"role": "user",
                                     "content": f"{user_text}\n\n[Nội dung file]\n```\n{decoded[:8000]}\n```"})
                    except Exception:
                        msgs.append({"role": "user", "content": user_text or ""})
            else:
                msgs.append({"role": "user", "content": user_text})
            r = await client.post(
                f"{p['base']}/messages",
                headers={"x-api-key": api_key, "anthropic-version": "2023-06-01"},
                json={"model": model, "max_tokens": 8096, "system": sys_msg, "messages": msgs},
            )
            _raise_for_provider(r, provider)
            return r.json()["content"][0]["text"]

        # -------- Gemini (v1beta) --------
        if kind == "gemini":
            contents = []
            for m in history:
                role = "model" if m["role"] == "assistant" else "user"
                contents.append({"role": role, "parts": [{"text": m["content"]}]})
            parts: list[dict[str, Any]] = [{"text": user_text or ""}]
            if img:
                media, data = img
                parts.append({"inline_data": {"mime_type": media, "data": data}})
            elif file_b64 and file_mime:
                if file_mime.startswith("image/"):
                    parts.append({"inline_data": {"mime_type": file_mime, "data": file_b64}})
                else:
                    try:
                        decoded = base64.b64decode(file_b64).decode("utf-8", errors="replace")
                        parts.append({"text": f"[Nội dung file]\n```\n{decoded[:8000]}\n```"})
                    except Exception:
                        pass
            contents.append({"role": "user", "parts": parts})
            url = f"{p['base']}/models/{model}:generateContent?key={api_key}"
            payload: dict[str, Any] = {
                "contents": contents,
                "systemInstruction": {"parts": [{"text": sys_msg}]},
                "generationConfig": {"maxOutputTokens": 8192},
            }
            r = await client.post(url, json=payload)
            _raise_for_provider(r, provider)
            data_r = r.json()
            # Trích xuất text an toàn
            try:
                return data_r["candidates"][0]["content"]["parts"][0]["text"]
            except (KeyError, IndexError):
                # Gemini đôi khi trả về finish_reason=SAFETY
                finish = data_r.get("candidates", [{}])[0].get("finishReason", "UNKNOWN")
                raise HTTPException(status_code=400,
                    detail=f"Gemini không trả về nội dung (finishReason={finish}). "
                           f"Có thể nội dung bị chặn bởi bộ lọc an toàn.")

    raise HTTPException(status_code=500, detail="Lỗi cấu hình provider.")


# ========================== FastAPI ==========================
app = FastAPI(title="KENIOS codebox", version="3.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_credentials=False, allow_methods=["*"], allow_headers=["*"])


@app.on_event("startup")
def _startup() -> None:
    init_db()


# ======================== Pydantic Models ========================
class RegisterIn(BaseModel):
    username: str
    password: str
    email: Optional[str] = None
    phone: Optional[str] = None

class LoginIn(BaseModel):
    username: str
    password: str

class ForgotIn(BaseModel):
    username: str

class ResetIn(BaseModel):
    token: str
    new_password: str

class ProfileIn(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    new_password: Optional[str] = None
    lang: Optional[str] = None          # "vi" | "en"

class KeyIn(BaseModel):
    provider: str
    api_key: str

class ChatIn(BaseModel):
    provider: str
    message: str = ""
    image: Optional[str] = None          # data:image/...;base64,... hoặc base64 thuần
    file_base64: Optional[str] = None    # file bất kỳ dạng base64
    file_mime: Optional[str] = None      # ví dụ: "application/pdf", "text/plain"
    model: Optional[str] = None
    conversation_id: Optional[int] = None
    api_key: Optional[str] = None
    system: Optional[str] = None         # system prompt tùy chỉnh

class EnsembleIn(BaseModel):
    providers: list[str]
    message: str
    judge: Optional[str] = None

class CodeRunIn(BaseModel):
    """Chạy code trên server (sandbox). Mặc định Python."""
    code: str
    stdin: Optional[str] = None
    language: Optional[str] = "python"

class FileRunIn(BaseModel):
    """Chạy test 1 file (Python/JS/Shell) từ thư viện file của người dùng."""
    file_id: int
    args: Optional[str] = None

class CodeReviewIn(BaseModel):
    """Nhờ AI review / debug / giải thích / chuyển đổi code."""
    provider: str
    code: str
    language: Optional[str] = None
    task: str = "review"   # "review" | "debug" | "explain" | "convert"
    target_lang: Optional[str] = None  # dùng khi task="convert"
    api_key: Optional[str] = None
    model: Optional[str] = None

class PaymentIn(BaseModel):
    amount: int   # VNĐ hoặc USD cent
    package: str  # "100k" | "300k" | "500k" | "pro_month"


# ======================== Health & Config ========================
@app.get("/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "time": int(time.time()), "version": "3.0",
            "providers": len(PROVIDERS)}


@app.get("/config")
def config() -> dict[str, Any]:
    return {"name": "KENIOS codebox", "version": "3.0",
            "providers": _providers_public()}


def _providers_public() -> list[dict[str, Any]]:
    return [
        {"id": k, "label": v["label"], "models": v["models"],
         "default_model": v["default_model"], "vision": v["vision"],
         "free": v["free"], "code": v.get("code", False)}
        for k, v in PROVIDERS.items()
    ]


@app.get("/providers")
def providers_list() -> list[dict[str, Any]]:
    return _providers_public()


# ======================== Auth ========================
@app.post("/auth/register")
def register(b: RegisterIn) -> dict[str, Any]:
    if len(b.username) < 3 or len(b.password) < 6:
        raise HTTPException(status_code=400,
            detail="Username ≥3 ký tự, mật khẩu ≥6 ký tự.")
    with db() as c:
        if c.execute("SELECT 1 FROM users WHERE username=?", (b.username,)).fetchone():
            raise HTTPException(status_code=409, detail="Username đã tồn tại.")
        cur = c.execute(
            "INSERT INTO users(username,email,phone,pw_hash,plan,credits,created_at) "
            "VALUES(?,?,?,?,'free',0,?)",
            (b.username, b.email, b.phone, hash_pw(b.password), int(time.time())),
        )
        uid = cur.lastrowid
    return {"token": make_token(uid),
            "user": {"id": uid, "username": b.username, "email": b.email,
                     "phone": b.phone, "is_admin": False, "plan": "free",
                     "credits": 0, "lang": "vi"}}


@app.post("/auth/login")
def login(b: LoginIn) -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE username=?", (b.username,)).fetchone()
    if not row or not verify_pw(b.password, row["pw_hash"]):
        raise HTTPException(status_code=401, detail="Sai username hoặc mật khẩu.")
    if row["banned"]:
        raise HTTPException(status_code=403, detail="Tài khoản đã bị khóa. Liên hệ quản trị viên.")
    return {"token": make_token(row["id"]),
            "user": {"id": row["id"], "username": row["username"],
                     "email": row["email"], "phone": row["phone"],
                     "is_admin": bool(row["is_admin"]), "plan": row["plan"],
                     "credits": row["credits"], "lang": row["lang"] or "vi"}}


@app.post("/auth/forgot-password")
def forgot(b: ForgotIn) -> dict[str, Any]:
    token = secrets.token_urlsafe(24)
    with db() as c:
        row = c.execute("SELECT id FROM users WHERE username=?", (b.username,)).fetchone()
        if row:
            c.execute("UPDATE users SET reset_token=?, reset_exp=? WHERE id=?",
                      (token, int(time.time()) + 1800, row["id"]))
    log.info("Reset token cho %s: %s", b.username, token)
    return {"message": "Nếu tài khoản tồn tại, mã đặt lại đã được tạo.",
            "reset_token": token}


@app.post("/auth/reset-password")
def reset_pw(b: ResetIn) -> dict[str, Any]:
    if len(b.new_password) < 6:
        raise HTTPException(status_code=400, detail="Mật khẩu mới ≥6 ký tự.")
    with db() as c:
        row = c.execute("SELECT id,reset_exp FROM users WHERE reset_token=?",
                        (b.token,)).fetchone()
        if not row or (row["reset_exp"] or 0) < time.time():
            raise HTTPException(status_code=400,
                detail="Mã đặt lại sai hoặc đã hết hạn (30 phút).")
        c.execute("UPDATE users SET pw_hash=?, reset_token=NULL, reset_exp=NULL WHERE id=?",
                  (hash_pw(b.new_password), row["id"]))
    return {"message": "Đổi mật khẩu thành công."}


@app.post("/auth/update-profile")
def update_profile(b: ProfileIn, user=Depends(get_user)) -> dict[str, Any]:
    fields, vals = [], []
    if b.email is not None:
        fields.append("email=?"); vals.append(b.email)
    if b.phone is not None:
        fields.append("phone=?"); vals.append(b.phone)
    if b.new_password:
        if len(b.new_password) < 6:
            raise HTTPException(status_code=400, detail="Mật khẩu mới ≥6 ký tự.")
        fields.append("pw_hash=?"); vals.append(hash_pw(b.new_password))
    if b.lang in ("vi", "en"):
        fields.append("lang=?"); vals.append(b.lang)
    if not fields:
        raise HTTPException(status_code=400, detail="Không có gì để cập nhật.")
    vals.append(user["id"])
    with db() as c:
        c.execute(f"UPDATE users SET {', '.join(fields)} WHERE id=?", vals)
    return {"message": "Cập nhật thành công."}


# ======================== API Keys ========================
@app.post("/keys")
def save_key(b: KeyIn, user=Depends(get_user)) -> dict[str, Any]:
    if b.provider not in PROVIDERS:
        raise HTTPException(status_code=400,
            detail=f"AI '{b.provider}' không được hỗ trợ. Danh sách hợp lệ: {list(PROVIDERS.keys())}")
    with db() as c:
        c.execute("INSERT INTO apikeys(user_id,provider,enc_key) VALUES(?,?,?) "
                  "ON CONFLICT(user_id,provider) DO UPDATE SET enc_key=excluded.enc_key",
                  (user["id"], b.provider, enc(b.api_key)))
    return {"message": f"Đã lưu API key cho {b.provider} thành công."}


@app.get("/keys")
def list_keys(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT provider FROM apikeys WHERE user_id=?",
                         (user["id"],)).fetchall()
    return [{"provider": r["provider"], "configured": True} for r in rows]


@app.delete("/keys/{provider}")
def del_key(provider: str, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM apikeys WHERE user_id=? AND provider=?",
                  (user["id"], provider))
    return {"message": f"Đã xóa key {provider}."}


@app.post("/keys/test")
async def test_key(b: KeyIn, user=Depends(get_user)) -> dict[str, Any]:
    """Gọi thử 1 câu ngắn để xem key dùng được không. Sai/hết hạn sẽ trả lỗi rõ ràng."""
    if b.provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"AI '{b.provider}' không được hỗ trợ.")
    try:
        await call_provider(b.provider, b.api_key, None, [], "ping")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400,
            detail=f"Key không dùng được: {type(e).__name__}: {str(e)[:200]}")
    return {"ok": True, "message": f"Key {b.provider} hoạt động tốt."}


# ======================== Chat ========================
def load_history(conversation_id: int, user_id: int) -> list[dict[str, str]]:
    with db() as c:
        own = c.execute("SELECT 1 FROM conversations WHERE id=? AND user_id=?",
                        (conversation_id, user_id)).fetchone()
        if not own:
            raise HTTPException(status_code=404, detail="Không tìm thấy hội thoại.")
        rows = c.execute(
            "SELECT role,content FROM messages WHERE conversation_id=? ORDER BY id",
            (conversation_id,)
        ).fetchall()
    return [{"role": r["role"], "content": r["content"]} for r in rows]


def new_conversation(user_id: int, provider: str, title: str) -> int:
    now = int(time.time())
    with db() as c:
        cur = c.execute(
            "INSERT INTO conversations(user_id,title,provider,created_at,updated_at) "
            "VALUES(?,?,?,?,?)",
            (user_id, (title or "Hội thoại mới")[:80], provider, now, now),
        )
        return cur.lastrowid


def save_message(conversation_id: int, role: str, content: str) -> None:
    with db() as c:
        c.execute("INSERT INTO messages(conversation_id,role,content,created_at) VALUES(?,?,?,?)",
                  (conversation_id, role, content, int(time.time())))
        c.execute("UPDATE conversations SET updated_at=? WHERE id=?",
                  (int(time.time()), conversation_id))


@app.post("/chat")
async def chat(b: ChatIn, user=Depends(get_user)) -> dict[str, Any]:
    if not b.message and not b.image and not b.file_base64:
        raise HTTPException(status_code=400,
            detail="Thiếu nội dung: cần ít nhất 'message', 'image', hoặc 'file_base64'.")
    key = get_user_key(user["id"], b.provider, b.api_key)
    conv_id = b.conversation_id or new_conversation(
        user["id"], b.provider, b.message or "File/Ảnh")
    history = load_history(conv_id, user["id"]) if b.conversation_id else []

    reply = await call_provider(
        b.provider, key, b.model, history,
        b.message, b.image,
        b.file_base64, b.file_mime,
        b.system,
    )
    save_message(conv_id, "user",
                 b.message or ("[ảnh]" if b.image else "[file]"))
    save_message(conv_id, "assistant", reply)
    saved_files = save_code_blocks(user["id"], reply, f"chat{conv_id}")
    return {"reply": reply, "conversation_id": conv_id, "provider": b.provider,
            "model": b.model or PROVIDERS[b.provider]["default_model"],
            "saved_files": saved_files}


@app.post("/chat/ensemble")
async def ensemble(b: EnsembleIn, user=Depends(get_user)) -> dict[str, Any]:
    """Hỏi nhiều AI cùng lúc, rồi 1 AI 'trọng tài' tổng hợp."""
    if len(b.providers) < 2:
        raise HTTPException(status_code=400, detail="Cần ít nhất 2 AI để ensemble.")

    async def one(prov: str):
        try:
            key = get_user_key(user["id"], prov, None)
            ans = await call_provider(prov, key, None, [], b.message)
            return prov, ans
        except HTTPException as e:
            return prov, f"[lỗi: {e.detail}]"

    results = await asyncio.gather(*[one(p) for p in b.providers])
    answers = {prov: ans for prov, ans in results}
    judge = b.judge or b.providers[0]
    judge_key = get_user_key(user["id"], judge, None)
    merged = (
        "Dưới đây là câu trả lời của nhiều AI cho cùng một câu hỏi. "
        "Hãy hợp nhất thành MỘT câu trả lời tốt nhất.\n\nCÂU HỎI:\n" + b.message
        + "\n\nCÁC CÂU TRẢ LỜI:\n"
        + "\n\n".join(f"### {p}\n{a}" for p, a in answers.items())
    )
    best = await call_provider(judge, judge_key, None, [], merged)
    return {"best": best, "judge": judge, "answers": answers}


# ======================== Lịch sử hội thoại ========================
@app.get("/conversations")
def list_conversations(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,title,provider,updated_at FROM conversations WHERE user_id=? "
            "ORDER BY updated_at DESC", (user["id"],)
        ).fetchall()
    return [dict(r) for r in rows]


@app.get("/conversations/{cid}")
def get_conversation(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    msgs = load_history(cid, user["id"])
    return {"conversation_id": cid, "messages": msgs}


@app.delete("/conversations/{cid}")
def delete_conversation(cid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM messages WHERE conversation_id=? AND conversation_id IN "
                  "(SELECT id FROM conversations WHERE user_id=?)", (cid, user["id"]))
        c.execute("DELETE FROM conversations WHERE id=? AND user_id=?", (cid, user["id"]))
    return {"message": "Đã xóa hội thoại."}


# ======================== Quản lý File ========================
MAX_FILE_B64 = 22_000_000  # ~16MB nhị phân

class FileIn(BaseModel):
    name: str
    category: Optional[str] = None
    mime: Optional[str] = None
    data_base64: str


@app.post("/files")
def upload_file(b: FileIn, user=Depends(get_user)) -> dict[str, Any]:
    if len(b.data_base64) > MAX_FILE_B64:
        raise HTTPException(status_code=413, detail="File quá lớn (giới hạn ~16MB).")
    size = (len(b.data_base64) * 3) // 4
    with db() as c:
        cur = c.execute(
            "INSERT INTO files(user_id,name,category,mime,size,data,created_at) "
            "VALUES(?,?,?,?,?,?,?)",
            (user["id"], b.name, b.category or _guess_category(b.name, b.mime),
             b.mime, size, b.data_base64, int(time.time())),
        )
        fid = cur.lastrowid
    return {"id": fid, "name": b.name, "size": size, "mime": b.mime}


def _guess_category(name: str, mime: Optional[str]) -> str:
    if mime and mime.startswith("image/"): return "image"
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if ext in ("py", "js", "ts", "swift", "kt", "go", "rs", "c", "cpp", "java",
               "php", "rb", "sh", "html", "css", "sql", "json", "yaml", "toml"):
        return "code"
    if ext in ("pdf", "docx", "doc", "txt", "md"): return "document"
    if mime and mime.startswith("image/"): return "image"
    return "other"


@app.get("/files")
def list_files(category: Optional[str] = None,
               user=Depends(get_user)) -> list[dict[str, Any]]:
    q = "SELECT id,name,category,mime,size,created_at FROM files WHERE user_id=?"
    args: list[Any] = [user["id"]]
    if category and category != "all":
        q += " AND category=?"; args.append(category)
    q += " ORDER BY id DESC"
    with db() as c:
        rows = c.execute(q, args).fetchall()
    return [dict(r) for r in rows]


@app.get("/files/{fid}")
def download_file(fid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        row = c.execute(
            "SELECT name,category,mime,data FROM files WHERE id=? AND user_id=?",
            (fid, user["id"])
        ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy file.")
    return {"name": row["name"], "category": row["category"],
            "mime": row["mime"], "data_base64": row["data"]}


@app.delete("/files/{fid}")
def delete_file(fid: int, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM files WHERE id=? AND user_id=?", (fid, user["id"]))
    return {"message": "Đã xóa file."}


# ======================== Chạy Code / Test ========================

# Cấu hình build/run cho từng ngôn ngữ.
#   src   = tên file nguồn trong thư mục tạm
#   check = lệnh cần có trên VPS (None = luôn có sẵn)
#   build = lệnh biên dịch (None nếu là ngôn ngữ thông dịch)
#   run   = lệnh chạy
LANG_SPECS: dict[str, dict[str, Any]] = {
    "python":     {"src": "main.py",   "check": None,    "build": None,                                       "run": [sys.executable, "main.py"]},
    "javascript": {"src": "main.js",   "check": "node",  "build": None,                                       "run": ["node", "main.js"]},
    "node":       {"src": "main.js",   "check": "node",  "build": None,                                       "run": ["node", "main.js"]},
    "typescript": {"src": "main.ts",   "check": "ts-node","build": None,                                      "run": ["ts-node", "main.ts"]},
    "bash":       {"src": "main.sh",   "check": "bash",  "build": None,                                       "run": ["bash", "main.sh"]},
    "shell":      {"src": "main.sh",   "check": "bash",  "build": None,                                       "run": ["bash", "main.sh"]},
    "php":        {"src": "main.php",  "check": "php",   "build": None,                                       "run": ["php", "main.php"]},
    "ruby":       {"src": "main.rb",   "check": "ruby",  "build": None,                                       "run": ["ruby", "main.rb"]},
    "c":          {"src": "main.c",    "check": "gcc",   "build": ["gcc", "main.c", "-o", "app"],             "run": ["./app"]},
    "cpp":        {"src": "main.cpp",  "check": "g++",   "build": ["g++", "main.cpp", "-o", "app", "-std=c++17"], "run": ["./app"]},
    "c++":        {"src": "main.cpp",  "check": "g++",   "build": ["g++", "main.cpp", "-o", "app", "-std=c++17"], "run": ["./app"]},
    "go":         {"src": "main.go",   "check": "go",    "build": None,                                       "run": ["go", "run", "main.go"]},
    "java":       {"src": "Main.java", "check": "javac", "build": ["javac", "Main.java"],                     "run": ["java", "Main"]},
    "rust":       {"src": "main.rs",   "check": "rustc", "build": ["rustc", "main.rs", "-o", "app"],          "run": ["./app"]},
}
INSTALL_HINT = {
    "node": "apt install -y nodejs npm", "ts-node": "npm install -g ts-node typescript",
    "php": "apt install -y php-cli", "ruby": "apt install -y ruby",
    "gcc": "apt install -y gcc", "g++": "apt install -y g++",
    "go": "apt install -y golang-go", "javac": "apt install -y default-jdk",
    "rustc": "apt install -y rustc",
}

@app.post("/run/code")
def run_code(b: CodeRunIn, user=Depends(get_user)) -> dict[str, Any]:
    """Chạy code nhiều ngôn ngữ (thông dịch & biên dịch). Mỗi ngôn ngữ cần trình tương ứng cài sẵn trên VPS."""
    lang = (b.language or "python").lower().strip()
    spec = LANG_SPECS.get(lang)
    if not spec:
        raise HTTPException(status_code=400,
            detail=f"Ngôn ngữ '{lang}' chưa hỗ trợ. Hỗ trợ: {sorted(set(LANG_SPECS))}")
    check = spec["check"]
    if check and shutil.which(check) is None:
        hint = INSTALL_HINT.get(check, "")
        raise HTTPException(status_code=400,
            detail=(f"Máy chủ chưa cài '{check}' để chạy {lang}. "
                    + (f"Cài trên VPS bằng: sudo {hint}" if hint else "Hãy cài trình này trên VPS.")))
    workdir = tempfile.mkdtemp(dir="/tmp", prefix="kenios_")
    try:
        with open(os.path.join(workdir, spec["src"]), "w", encoding="utf-8") as f:
            f.write(b.code)
        # Bước biên dịch (nếu có)
        if spec["build"]:
            cp = subprocess.run(spec["build"], cwd=workdir,
                                capture_output=True, text=True, timeout=SANDBOX_TIMEOUT)
            if cp.returncode != 0:
                return {"stdout": cp.stdout[:4000],
                        "stderr": "[Lỗi biên dịch]\n" + cp.stderr[:4000],
                        "returncode": cp.returncode, "language": lang}
        # Bước chạy
        rp = subprocess.run(spec["run"], cwd=workdir, input=b.stdin or "",
                            capture_output=True, text=True, timeout=SANDBOX_TIMEOUT)
        return {"stdout": rp.stdout[:8000], "stderr": rp.stderr[:2000],
                "returncode": rp.returncode, "language": lang}
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": f"Timeout sau {SANDBOX_TIMEOUT} giây.",
                "returncode": -1, "language": lang}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": -2, "language": lang}
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


@app.post("/run/python")
def run_python(b: CodeRunIn, user=Depends(get_user)) -> dict[str, Any]:
    """
    Chạy đoạn code Python trong sandbox (subprocess, isolated).
    Giới hạn: SANDBOX_TIMEOUT giây, 64MB RAM (ulimit nếu có).
    """
    with tempfile.NamedTemporaryFile(mode="w", suffix=".py",
                                     delete=False, dir="/tmp") as f:
        f.write(b.code)
        tmp = f.name
    try:
        result = subprocess.run(
            [sys.executable, tmp],
            input=b.stdin or "",
            capture_output=True,
            text=True,
            timeout=SANDBOX_TIMEOUT,
        )
        return {
            "stdout": result.stdout[:8000],
            "stderr": result.stderr[:2000],
            "returncode": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": f"Timeout sau {SANDBOX_TIMEOUT} giây.",
                "returncode": -1}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": -2}
    finally:
        try: os.unlink(tmp)
        except Exception: pass


@app.post("/run/test")
def run_test_file(b: FileRunIn, user=Depends(get_user)) -> dict[str, Any]:
    """
    Chạy test một file từ thư viện file của người dùng.
    Hỗ trợ: .py  (Python), .js (Node.js nếu có), .sh (Shell).
    """
    with db() as c:
        row = c.execute("SELECT name,mime,data FROM files WHERE id=? AND user_id=?",
                        (b.file_id, user["id"])).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy file.")
    try:
        code_bytes = base64.b64decode(row["data"])
        code_text  = code_bytes.decode("utf-8", errors="replace")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Không đọc được file: {e}")

    name = row["name"]
    ext  = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    suffix_map = {"py": ".py", "js": ".js", "sh": ".sh"}
    runner_map = {"py": [sys.executable], "js": ["node"], "sh": ["bash"]}
    if ext not in suffix_map:
        raise HTTPException(status_code=400,
            detail=f"Định dạng '{ext}' chưa hỗ trợ chạy test. Hỗ trợ: py, js, sh.")

    with tempfile.NamedTemporaryFile(mode="w", suffix=suffix_map[ext],
                                     delete=False, dir="/tmp") as f:
        f.write(code_text)
        tmp = f.name
    try:
        cmd = runner_map[ext] + [tmp]
        if b.args:
            cmd += b.args.split()
        result = subprocess.run(cmd, capture_output=True, text=True,
                                timeout=SANDBOX_TIMEOUT)
        return {
            "file": name, "stdout": result.stdout[:8000],
            "stderr": result.stderr[:2000],
            "returncode": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"file": name, "stdout": "",
                "stderr": f"Timeout sau {SANDBOX_TIMEOUT} giây.", "returncode": -1}
    except FileNotFoundError as e:
        return {"file": name, "stdout": "",
                "stderr": f"Chưa cài runtime: {e}", "returncode": -3}
    finally:
        try: os.unlink(tmp)
        except Exception: pass


# ======================== Code AI Tools ========================
CODE_PROMPTS = {
    "review":  "Hãy review code sau, chỉ ra lỗi, cải tiến, best practice:\n\n```{lang}\n{code}\n```",
    "debug":   "Tìm và sửa lỗi trong đoạn code sau, giải thích từng lỗi:\n\n```{lang}\n{code}\n```",
    "explain": "Giải thích chi tiết đoạn code sau (bằng tiếng Việt):\n\n```{lang}\n{code}\n```",
    "convert": "Chuyển đoạn code {lang} sau sang {target_lang}, giữ nguyên logic:\n\n```{lang}\n{code}\n```",
    "test":    "Viết unit test cho đoạn code {lang} sau (dùng framework phổ biến nhất):\n\n```{lang}\n{code}\n```",
    "optimize":"Tối ưu hiệu năng đoạn code {lang} sau, giải thích từng thay đổi:\n\n```{lang}\n{code}\n```",
    "document":"Viết documentation (docstring/comment) cho đoạn code {lang} sau:\n\n```{lang}\n{code}\n```",
    "security":"Kiểm tra bảo mật đoạn code {lang} sau, liệt kê lỗ hổng và cách vá:\n\n```{lang}\n{code}\n```",
}


@app.post("/code/ai")
async def code_ai(b: CodeReviewIn, user=Depends(get_user)) -> dict[str, Any]:
    """Review, debug, explain, convert, test, optimize, document, security."""
    task = b.task.lower()
    if task not in CODE_PROMPTS:
        raise HTTPException(status_code=400,
            detail=f"Task '{task}' không hợp lệ. Hỗ trợ: {list(CODE_PROMPTS.keys())}")
    lang = b.language or "python"
    prompt = CODE_PROMPTS[task].format(
        lang=lang, code=b.code[:12000],
        target_lang=b.target_lang or "JavaScript",
    )
    key = get_user_key(user["id"], b.provider, b.api_key)
    result = await call_provider(b.provider, key, b.model, [], prompt)
    saved_files = save_code_blocks(user["id"], result, f"laptrinh_{task}")
    return {"result": result, "task": task, "provider": b.provider,
            "saved_files": saved_files}


# ======================== Giọng nói ========================
@app.post("/voice/transcribe")
async def transcribe(request: Request, user=Depends(get_user)) -> dict[str, Any]:
    """
    Chuyển audio → văn bản.
    JSON: {
      "provider": "openai",          // hoặc "groq" (Whisper-compatible)
      "audio_base64": "...",
      "mime": "audio/m4a",           // audio/mp3, audio/wav, audio/webm
      "api_key": "..."               // tùy chọn
    }
    """
    body = await request.json()
    prov  = body.get("provider", "openai")
    audio_b64 = body.get("audio_base64")
    if not audio_b64:
        raise HTTPException(status_code=400, detail="Thiếu 'audio_base64'.")

    # Groq cũng hỗ trợ Whisper-compatible
    if PROVIDERS.get(prov, {}).get("kind") != "openai":
        raise HTTPException(status_code=400,
            detail="Phiên âm giọng nói chỉ hỗ trợ provider kiểu OpenAI "
                   "(openai hoặc groq). Vui lòng chọn lại.")
    key   = get_user_key(user["id"], prov, body.get("api_key"))
    mime  = body.get("mime", "audio/m4a")
    ext_map = {"audio/m4a": "m4a", "audio/mp3": "mp3", "audio/mpeg": "mp3",
               "audio/wav": "wav", "audio/webm": "webm", "audio/ogg": "ogg"}
    ext   = ext_map.get(mime, "m4a")
    audio = base64.b64decode(audio_b64)

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.post(
            f"{PROVIDERS[prov]['base']}/audio/transcriptions",
            headers={"Authorization": f"Bearer {key}"},
            files={"file": (f"audio.{ext}", audio, mime)},
            data={"model": body.get("model", "whisper-1"),
                  "language": body.get("language", "vi")},
        )
    _raise_for_provider(r, prov)
    return {"text": r.json().get("text", ""),
            "provider": prov, "language": body.get("language", "vi")}


# ======================== Thanh toán / Credits ========================
PACKAGES = {
    "100k":      {"credits": 100,  "amount": 100000,  "label": "100 credits - 100.000đ"},
    "300k":      {"credits": 350,  "amount": 300000,  "label": "350 credits - 300.000đ"},
    "500k":      {"credits": 650,  "amount": 500000,  "label": "650 credits - 500.000đ"},
    "pro_month": {"credits": 9999, "amount": 199000,  "label": "Pro tháng - 199.000đ"},
}


@app.get("/payment/packages")
def payment_packages() -> list[dict[str, Any]]:
    return [{"id": k, **v} for k, v in PACKAGES.items()]


@app.post("/payment/create")
def payment_create(b: PaymentIn, user=Depends(get_user)) -> dict[str, Any]:
    if b.package not in PACKAGES:
        raise HTTPException(status_code=400,
            detail=f"Gói không hợp lệ. Chọn: {list(PACKAGES.keys())}")
    pkg = PACKAGES[b.package]
    ref = secrets.token_urlsafe(16)
    with db() as c:
        cur = c.execute(
            "INSERT INTO payments(user_id,amount,credits,status,ref,created_at) "
            "VALUES(?,?,?,'pending',?,?)",
            (user["id"], pkg["amount"], pkg["credits"], ref, int(time.time())),
        )
        pid = cur.lastrowid
    bank = bank_info(amount=pkg["amount"], note=f"KENIOS {ref}")
    return {
        "payment_id": pid,
        "ref": ref,
        "amount": pkg["amount"],
        "credits": pkg["credits"],
        "label": pkg["label"],
        "message": "Quét mã QR hoặc chuyển khoản theo thông tin bên dưới. Admin sẽ xác nhận khi nhận được tiền.",
        "bank_info": bank,
        "qr_url": bank["qr_url"],
    }


def bank_info(amount: int = 0, note: str = "KENIOS") -> dict[str, Any]:
    from urllib.parse import quote
    code = get_setting("bank_code", "970416")
    short = get_setting("bank_short", "ACB")
    account = get_setting("bank_account", "23252921")
    name = get_setting("bank_name", "TRAN MINH CHIEN")
    qr = (f"https://img.vietqr.io/image/{code}-{account}-compact2.png"
          f"?accountName={quote(name)}&addInfo={quote(note)}")
    if amount > 0:
        qr += f"&amount={amount}"
    return {"bank": short, "bank_code": code, "account": account,
            "name": name, "content": note, "qr_url": qr}


@app.get("/payment/info")
def payment_info(amount: int = 0, note: str = "KENIOS", user=Depends(get_user)) -> dict[str, Any]:
    return bank_info(amount=amount, note=note)


class BankSettingsIn(BaseModel):
    bank_code: Optional[str] = None
    bank_short: Optional[str] = None
    bank_account: Optional[str] = None
    bank_name: Optional[str] = None
    bank_webhook: Optional[str] = None
    bank_apikey: Optional[str] = None

@app.get("/admin/payment/settings")
def admin_get_bank(admin=Depends(get_admin)) -> dict[str, Any]:
    return {
        "bank_code": get_setting("bank_code", "970416"),
        "bank_short": get_setting("bank_short", "ACB"),
        "bank_account": get_setting("bank_account", "23252921"),
        "bank_name": get_setting("bank_name", "TRAN MINH CHIEN"),
        "bank_webhook": get_setting("bank_webhook", ""),
        "bank_apikey": get_setting("bank_apikey", ""),
    }

@app.post("/admin/payment/settings")
def admin_set_bank(b: BankSettingsIn, admin=Depends(get_admin)) -> dict[str, Any]:
    for field in ["bank_code", "bank_short", "bank_account", "bank_name", "bank_webhook", "bank_apikey"]:
        val = getattr(b, field)
        if val is not None:
            set_setting(field, val)
    return {"message": "Đã cập nhật thông tin ngân hàng."}


@app.post("/payment/confirm/{pid}")
def payment_confirm(pid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    """Admin xác nhận thanh toán thủ công."""
    with db() as c:
        pay = c.execute("SELECT * FROM payments WHERE id=?", (pid,)).fetchone()
        if not pay:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn thanh toán.")
        if pay["status"] == "completed":
            raise HTTPException(status_code=400, detail="Đơn đã được xác nhận trước đó.")
        c.execute("UPDATE payments SET status='completed' WHERE id=?", (pid,))
        c.execute("UPDATE users SET credits=credits+? WHERE id=?",
                  (pay["credits"], pay["user_id"]))
        # Nâng cấp plan nếu là gói pro
        if pay["credits"] >= 9999:
            c.execute("UPDATE users SET plan='pro' WHERE id=?", (pay["user_id"],))
    return {"message": f"Đã cộng {pay['credits']} credits cho user {pay['user_id']}."}


@app.get("/payment/history")
def payment_history(user=Depends(get_user)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,amount,credits,status,ref,created_at FROM payments "
            "WHERE user_id=? ORDER BY id DESC", (user["id"],)
        ).fetchall()
    return [dict(r) for r in rows]


@app.get("/me/credits")
def my_credits(user=Depends(get_user)) -> dict[str, Any]:
    return {"credits": user["credits"], "plan": user["plan"]}


# ======================== Admin ========================
class BanIn(BaseModel):   banned: bool
class AdminPwIn(BaseModel): new_password: str
class PlanIn(BaseModel):   plan: str

@app.get("/admin/users")
def admin_users(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute(
            "SELECT id,username,email,phone,is_admin,banned,plan,credits,created_at "
            "FROM users ORDER BY id"
        ).fetchall()
    return [dict(r) for r in rows]


@app.post("/admin/users/{uid}/ban")
def admin_ban(uid: int, b: BanIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if uid == admin["id"]:
        raise HTTPException(status_code=400, detail="Không thể tự khóa chính mình.")
    with db() as c:
        c.execute("UPDATE users SET banned=? WHERE id=?", (1 if b.banned else 0, uid))
    return {"message": "Đã khóa." if b.banned else "Đã mở khóa."}


@app.post("/admin/users/{uid}/password")
def admin_set_pw(uid: int, b: AdminPwIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if len(b.new_password) < 6:
        raise HTTPException(status_code=400, detail="Mật khẩu ≥6 ký tự.")
    with db() as c:
        c.execute("UPDATE users SET pw_hash=? WHERE id=?",
                  (hash_pw(b.new_password), uid))
    return {"message": "Đã đổi mật khẩu."}


@app.post("/admin/users/{uid}/plan")
def admin_set_plan(uid: int, b: PlanIn, admin=Depends(get_admin)) -> dict[str, Any]:
    if b.plan not in ("free", "pro"):
        raise HTTPException(status_code=400, detail="Gói không hợp lệ.")
    with db() as c:
        c.execute("UPDATE users SET plan=? WHERE id=?", (b.plan, uid))
    return {"message": f"Đã đặt gói '{b.plan}'."}


@app.post("/admin/payments/{pid}/confirm")
def admin_confirm_payment(pid: int, admin=Depends(get_admin)) -> dict[str, Any]:
    return payment_confirm(pid, admin)


# ======================== Báo lỗi & log lỗi cho admin ========================
class ErrorIn(BaseModel):
    context: str = ""
    detail: str = ""

@app.post("/errors")
def report_error(b: ErrorIn, user=Depends(get_user)) -> dict[str, Any]:
    with db() as c:
        c.execute("INSERT INTO error_logs(user_id,username,context,detail,created_at) "
                  "VALUES(?,?,?,?,?)",
                  (user["id"], user["username"], b.context[:200], b.detail[:800], int(time.time())))
    return {"message": "Đã ghi nhận lỗi."}

@app.get("/admin/errors")
def admin_errors(admin=Depends(get_admin)) -> list[dict[str, Any]]:
    with db() as c:
        rows = c.execute("SELECT id,user_id,username,context,detail,created_at "
                         "FROM error_logs ORDER BY id DESC LIMIT 200").fetchall()
    return [dict(r) for r in rows]

@app.delete("/admin/errors")
def admin_clear_errors(admin=Depends(get_admin)) -> dict[str, Any]:
    with db() as c:
        c.execute("DELETE FROM error_logs")
    return {"message": "Đã xóa toàn bộ log lỗi."}


# ======================== Error handler ========================
@app.exception_handler(Exception)
async def on_error(request: Request, exc: Exception):
    log.exception("Lỗi server: %s", exc)
    # Ghi log lỗi để admin xem
    try:
        with db() as c:
            c.execute("INSERT INTO error_logs(context,detail,created_at) VALUES(?,?,?)",
                      (str(request.url.path), f"{type(exc).__name__}: {exc}"[:800], int(time.time())))
    except Exception:
        pass
    return JSONResponse(status_code=500,
                        content={"detail": f"Lỗi máy chủ: {type(exc).__name__}: {str(exc)[:300]}"})


# ======================== Entrypoint ========================
if __name__ == "__main__":
    import uvicorn
    init_db()
    log.info("KENIOS codebox v3.0 — cổng %s | %d AI hỗ trợ", PORT, len(PROVIDERS))
    uvicorn.run(app, host="0.0.0.0", port=PORT)


# ==================================================================
# CHẠY 24/7 BẰNG systemd:
#
#   [Unit]
#   Description=KENIOS codebox v3
#   After=network.target
#
#   [Service]
#   WorkingDirectory=/root/kenios
#   Environment=CODEBOX_SECRET=doi-thanh-chuoi-bi-mat-cua-ban
#   Environment=ADMIN_USER=kenios
#   Environment=ADMIN_PASS=MatKhauManhCuaBan!
#   Environment=BANK_ACCOUNT=0123456789
#   Environment=BANK_NAME=NGUYEN VAN A
#   ExecStart=/root/kenios/venv/bin/uvicorn codebox:app --host 0.0.0.0 --port 8000
#   Restart=always
#   RestartSec=5
#
#   [Install]
#   WantedBy=multi-user.target
#
#   Lệnh:
#     sudo systemctl daemon-reload
#     sudo systemctl enable --now codebox
#     sudo systemctl status codebox
# ==================================================================
