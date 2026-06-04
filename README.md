# MinerU Auto-Convert Hook for Claude Code

[🇨🇳 中文文档](README_ZH.md)

**PDF / DOCX / PPTX / XLSX → Markdown, automatically. Before Claude reads a document, this hook converts it to clean, structured markdown via the [MinerU](https://github.com/opendatalab/MinerU) API.**

> Powered by [**MinerU API v4**](https://mineru.net) from [OpenDataLab](https://github.com/opendatalab/MinerU). For an MCP-server approach, see [mineru-mcp](https://github.com/linxule/mineru-mcp).

## What it does

```
Model says: "Read this PDF"
    ↓
Hook intercepts → Uploads to MinerU API → Polls for completion
    ↓
Downloads markdown → Caches locally (7 days)
    ↓
Model reads the clean .md instead of the raw PDF
```

The model never sees the binary file. It only reads structured markdown — with tables, headings, images, and layout preserved.

## Supported formats

All formats MinerU API v4 can parse — maximum coverage:

| Category | Extensions |
|----------|-----------|
| PDF | `.pdf` |
| Word | `.docx` `.doc` `.rtf` `.odt` |
| Excel | `.xlsx` `.xls` `.csv` |
| PowerPoint | `.pptx` `.ppt` |
| Images (OCR) | `.png` `.jpg` `.jpeg` `.gif` `.webp` `.bmp` `.tiff` `.tif` `.ico` `.heic` `.heif` |
| E-books | `.epub` `.mobi` |
| Markup | `.html` `.htm` `.xml` |

> **Note:** Native text formats (`.txt`, `.md`, `.json`) are already readable by Claude — the hook skips them to avoid unnecessary API calls.

## Performance

Measured on real documents:

| Document | Original | MinerU Output | Conversion | Token Saving |
|----------|----------|---------------|------------|--------------|
| PDF (13p, Chinese) | 1.4 MB | 8.8 KB | 11.1s | — |
| DOCX (tables+images) | 1.0 MB | 11.9 KB | 11.5s | **23% fewer tokens** vs raw extraction |
| Cache hit (re-read) | — | — | **0s** | Instant |

## Quick Start

### One-click setup

```bash
bash setup.sh
```

This installs the hook script, configures your API key, and sets up caching.

### Manual setup

```bash
# 1. Copy the hook
cp mineru-auto-hook.py ~/.claude/scripts/

# 2. Set your API key
echo 'MINERU_API_KEY=your-jwt-token' >> ~/.claude/.secrets
chmod 600 ~/.claude/.secrets

# 3. Add to ~/.claude/settings.json under hooks → PreToolUse:
# In the "Read" matcher, add:
# {
#   "type": "command",
#   "command": "python3 ~/.claude/scripts/mineru-auto-hook.py",
#   "timeout": 600
# }

# 4. Restart Claude Code
```

## Getting a MinerU API Key

This hook uses the **MinerU API v4** from [mineru.net](https://mineru.net), the cloud service built by the [MinerU](https://github.com/opendatalab/MinerU) open-source project.

1. Visit **[https://mineru.net](https://mineru.net)** and register an account
2. Go to **Console → API Management** (控制台 → API 管理)
3. Click **Create API Key** (创建 API Key)
4. Copy the JWT token — it looks like: `eyJ0eXBlIjoiSldUIi...`
5. Run `bash setup.sh` or save it to `~/.claude/.secrets`

> **Note:** The free tier includes a quota of document pages per month. Check [mineru.net](https://mineru.net) for current limits.

## How to verify it's working

```bash
# Check the event log
cat ~/.claude/mineru-cache/hook.log

# Example output:
# {"ts":"2026-06-04T19:52:47Z","event":"convert_start","file":"report.pdf","detail":"size=1.4MB ext=.pdf"}
# {"ts":"2026-06-04T19:52:58Z","event":"convert_done","file":"report.pdf","detail":"elapsed=11.1s md_size=8984B"}

# List cached conversions
ls -lh ~/.claude/mineru-cache/*.md
```

**Log events:**

| Event | Meaning |
|-------|---------|
| `convert_start` | Hook triggered, uploading to MinerU |
| `convert_done` | Conversion complete, cached |
| `cache_hit` | File already converted, instant redirect |
| `convert_error` | Conversion failed (see detail for reason) |
| `skip_no_key` | API key not configured |

## How it works

1. **PreToolUse hook** intercepts every `Read` tool call
2. Checks if the file extension is in the convertible list (`.pdf`, `.docx`, `.pptx`, `.xlsx`, etc.)
3. Checks the cache (`~/.claude/mineru-cache/{md5}.md`) — returns instantly if valid
4. Uploads to MinerU API, polls for completion (up to 7.5 min timeout)
5. Downloads the result zip, extracts `full.md`, caches it
6. **Redirects** the Read to the cached markdown — the model only sees clean text

## Files

```
mineru-auto-hook/
├── mineru-auto-hook.py   # Main hook script (Python 3, stdlib only)
├── setup.sh               # One-click interactive installer
├── .gitignore
├── README.md              # English docs
└── README_ZH.md           # Chinese docs
```

## Requirements

- **Python 3.9+** (stdlib only — no pip install needed)
- **unzip** (macOS/Linux: pre-installed)
- **Claude Code** with hooks enabled
- **MinerU API key** (free registration at [mineru.net](https://mineru.net))

## Credits

- **[MinerU](https://github.com/opendatalab/MinerU)** — OpenDataLab's open-source document parsing engine
- **[mineru-mcp](https://github.com/linxule/mineru-mcp)** — MCP server wrapper for MinerU (alternative approach)
- **[mineru.net](https://mineru.net)** — Cloud API service by OpenXLab

## License

MIT — use it, fork it, ship it.
