#!/usr/bin/env python3
"""
MinerU Auto-Convert Hook — intercepts Read on convertible documents,
auto-converts via MinerU API, caches result, redirects Read to markdown.

Activation: all models. Only for non-image documents (images → ai-vision-hook).
Cache: ~/.claude/mineru-cache/{md5}.md  (7-day TTL)

Based on mineru-mcp (https://github.com/opendatalab/MinerU)
Uses MinerU API v4 for document parsing.
"""
import sys, os, json, time, hashlib, shutil, subprocess, urllib.request, urllib.error

# ── Config ────────────────────────────────────────────────────
API_BASE = "https://mineru.net/api/v4"
MODEL = os.environ.get("MINERU_DEFAULT_MODEL", "pipeline")
CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mineru-cache")

# ── API Key resolution (env var → .secrets file fallback) ─
API_KEY = os.environ.get("MINERU_API_KEY", "")
if not API_KEY:
    secrets_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".secrets")
    if os.path.isfile(secrets_file):
        try:
            with open(secrets_file) as sf:
                for line in sf:
                    line = line.strip()
                    if line.startswith("MINERU_API_KEY="):
                        API_KEY = line.split("=", 1)[1].strip().strip('"').strip("'")
                        break
        except Exception:
            pass

# Supported extensions — EXCLUDE image types that ai-vision-hook handles
CONVERT_EXT = {".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx"}
VISION_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif", ".ico", ".heic", ".heif"}


def ok():
    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}
    }, ensure_ascii=False))
    sys.stdout.flush()


def redirect(file_path):
    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": {"file_path": file_path}
        }
    }, ensure_ascii=False))
    sys.stdout.flush()


def api_request(endpoint, method="GET", data=None, timeout=30):
    url = f"{API_BASE}{endpoint}"
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, method=method,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {API_KEY}"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=timeout) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    if result.get("code") != 0:
        raise RuntimeError(f"MinerU API error {result.get('code')}: {result.get('msg', 'unknown')}")
    return result["data"]


def convert_file(file_path):
    """Upload + poll + download → return path to cached .md file."""
    fhash = hashlib.md5(file_path.encode()).hexdigest()
    cache_path = os.path.join(CACHE_DIR, fhash + ".md")

    if os.path.exists(cache_path):
        if os.path.getmtime(cache_path) >= os.path.getmtime(file_path):
            return cache_path

    file_name = os.path.basename(file_path)
    stem, _ = os.path.splitext(file_name)
    stem = stem.replace(" ", "_")[:128]
    file_size = os.path.getsize(file_path)
    if file_size > 200 * 1024 * 1024:
        raise RuntimeError(f"File too large ({file_size // 1024 // 1024}MB), max 200MB")

    # 1. Request presigned upload URL
    upload_res = api_request("/file-urls/batch", "POST", {
        "files": [{"name": file_name, "data_id": stem}],
        "model_version": MODEL,
    }, timeout=15)
    batch_id = upload_res["batch_id"]
    upload_url = upload_res["file_urls"][0]

    # 2. Upload file via PUT — must NOT send Content-Type or OSS signature fails
    with open(file_path, "rb") as f:
        file_data = f.read()
    req = urllib.request.Request(upload_url, data=file_data, method="PUT")
    req.add_header("Content-Type", "")  # suppress urllib's auto Content-Type
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    upload_timeout = max(60, 60 + (file_size // (1024 * 1024)) * 2)
    with opener.open(req, timeout=upload_timeout) as resp:
        if resp.status not in (200, 204):
            raise RuntimeError(f"Upload failed: HTTP {resp.status}")

    # 3. Poll for completion
    for _ in range(90):
        time.sleep(5)
        try:
            status = api_request(f"/extract-results/batch/{batch_id}", timeout=10)
        except Exception:
            continue
        r = status["extract_result"][0]
        if r["state"] == "done" and r.get("full_zip_url"):
            zip_url = r["full_zip_url"]
            break
        elif r["state"] == "failed":
            raise RuntimeError(f"Parse failed: {r.get('err_msg', 'unknown')}")
    else:
        raise RuntimeError("MinerU processing timed out after 7.5 min")

    # 4. Download zip & extract full.md
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp_zip = os.path.join(CACHE_DIR, fhash + ".zip")
    tmp_extract = os.path.join(CACHE_DIR, fhash + "_extract")

    try:
        urllib.request.urlretrieve(zip_url, tmp_zip)
        os.makedirs(tmp_extract, exist_ok=True)
        subprocess.run(["unzip", "-o", "-q", tmp_zip, "-d", tmp_extract],
                       check=True, timeout=60, capture_output=True)

        md_found = None
        for root, dirs, files in os.walk(tmp_extract):
            if root[len(tmp_extract):].count(os.sep) > 5:
                dirs.clear()
                continue
            for fn in files:
                if fn == "full.md":
                    md_found = os.path.join(root, fn)
                    break
            if md_found:
                break
        if not md_found:
            raise RuntimeError("full.md not found in extracted zip")

        shutil.copyfile(md_found, cache_path)
        return cache_path
    finally:
        if os.path.exists(tmp_zip):
            os.unlink(tmp_zip)
        shutil.rmtree(tmp_extract, ignore_errors=True)


def log_event(event, file_path="", detail=""):
    """Write structured log line to mineru-cache/hook.log (JSON lines)."""
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        log_path = os.path.join(CACHE_DIR, "hook.log")
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "event": event,
            "file": os.path.basename(file_path) if file_path else "",
            "detail": str(detail)[:200],
        }
        with open(log_path, "a") as lf:
            lf.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


def cleanup_expired():
    try:
        if not os.path.isdir(CACHE_DIR):
            return
        now = time.time()
        for fn in os.listdir(CACHE_DIR):
            fp = os.path.join(CACHE_DIR, fn)
            if os.path.isfile(fp) and now - os.path.getmtime(fp) > 604800:
                os.unlink(fp)
        for fn in os.listdir(CACHE_DIR):
            fp = os.path.join(CACHE_DIR, fn)
            if os.path.isdir(fp) and fn.endswith("_extract") and now - os.path.getmtime(fp) > 86400:
                shutil.rmtree(fp, ignore_errors=True)
    except Exception:
        pass


def main():
    cleanup_expired()

    if not API_KEY:
        log_event("skip_no_key", "", "MINERU_API_KEY not set")
        return ok()

    try:
        raw = sys.stdin.read()
        hook = json.loads(raw) if raw.strip() else {}
    except Exception:
        return ok()

    if hook.get("tool_name") != "Read":
        return ok()

    fp = hook.get("tool_input", {}).get("file_path", "")
    if not fp or not os.path.isfile(fp):
        return ok()

    ext = os.path.splitext(fp)[1].lower()
    if ext in VISION_EXT or ext not in CONVERT_EXT:
        return ok()

    # ── Hook is triggering ──
    fsize_mb = os.path.getsize(fp) / (1024 * 1024)
    fhash = hashlib.md5(fp.encode()).hexdigest()
    cache_path = os.path.join(CACHE_DIR, fhash + ".md")

    if os.path.exists(cache_path) and os.path.getmtime(cache_path) >= os.path.getmtime(fp):
        log_event("cache_hit", fp, f"cached={fhash}.md")
        return redirect(cache_path)

    log_event("convert_start", fp, f"size={fsize_mb:.1f}MB ext={ext}")
    t0 = time.time()
    try:
        md_path = convert_file(fp)
        elapsed = time.time() - t0
        md_size = os.path.getsize(md_path) if os.path.isfile(md_path) else 0
        log_event("convert_done", fp, f"elapsed={elapsed:.1f}s md_size={md_size}B")
        redirect(md_path)
    except Exception as e:
        elapsed = time.time() - t0
        log_event("convert_error", fp, f"elapsed={elapsed:.1f}s error={e}")
        return ok()


if __name__ == "__main__":
    main()
