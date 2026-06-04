# MinerU 自动转换 Hook for Claude Code

[🇺🇸 English](README.md)

**PDF / DOCX / PPTX / XLSX → Markdown，全自动。Claude 读取文档前，Hook 通过 [MinerU](https://github.com/opendatalab/MinerU) API 将其转换为结构化 Markdown。**

> 基于 [**mineru-mcp**](https://github.com/opendatalab/MinerU) — OpenDataLab / OpenXLab 出品的开源文档解析引擎。

## 它能做什么

```
模型说："读取这个 PDF"
    ↓
Hook 拦截 → 上传到 MinerU API → 轮询等待完成
    ↓
下载 Markdown → 本地缓存（7 天有效）
    ↓
模型读到的是干净的 .md，而不是原始 PDF 二进制
```

模型完全不需要接触二进制文件。它只读到结构化 Markdown —— 保留表格、标题、图片位置和排版布局。

## 支持的格式

MinerU API v4 能解析的所有格式 — 最大覆盖：

| 类别 | 扩展名 |
|----------|-----------|
| PDF | `.pdf` |
| Word | `.docx` `.doc` `.rtf` `.odt` |
| Excel | `.xlsx` `.xls` `.csv` |
| PowerPoint | `.pptx` `.ppt` |
| 图片（OCR） | `.png` `.jpg` `.jpeg` `.gif` `.webp` `.bmp` `.tiff` `.tif` `.ico` `.heic` `.heif` |
| 电子书 | `.epub` `.mobi` |
| 标记语言 | `.html` `.htm` `.xml` |

> **注意：** 纯文本格式（`.txt`、`.md`、`.json`）Claude 本身就能读 — Hook 会跳过它们，避免不必要的 API 调用。

## 实测性能

真实文档测试数据：

| 文档 | 原始大小 | MinerU 输出 | 转换耗时 | Token 节省 |
|----------|----------|---------------|------------|--------------|
| PDF（13 页，中文） | 1.4 MB | 8.8 KB | 11.1 秒 | — |
| DOCX（含表格+图片） | 1.0 MB | 11.9 KB | 11.5 秒 | 比直接提取文本 **省 23% Token** |
| 缓存命中（二次读取） | — | — | **0 秒** | 即时 |

## 快速开始

### 一键安装

```bash
bash setup.sh
```

自动完成：安装脚本 → 配置 API Key → 创建缓存目录 → 配置 Hook。

### 手动安装

```bash
# 1. 复制 hook 脚本
cp mineru-auto-hook.py ~/.claude/scripts/

# 2. 设置 API Key
echo 'MINERU_API_KEY=你的jwt令牌' >> ~/.claude/.secrets
chmod 600 ~/.claude/.secrets

# 3. 在 ~/.claude/settings.json 的 hooks → PreToolUse 中添加：
# 在 "Read" matcher 下添加:
# {
#   "type": "command",
#   "command": "python3 ~/.claude/scripts/mineru-auto-hook.py",
#   "timeout": 600
# }

# 4. 重启 Claude Code
```

## 如何获取 MinerU API Key

本 Hook 使用 [mineru.net](https://mineru.net) 提供的 **MinerU API v4**，这是 [MinerU](https://github.com/opendatalab/MinerU) 开源项目的云服务。

1. 访问 **[https://mineru.net](https://mineru.net)** 注册账号
2. 进入 **控制台 → API 管理**
3. 点击 **创建 API Key**
4. 复制 JWT 令牌，格式类似：`eyJ0eXBlIjoiSldUIi...`
5. 运行 `bash setup.sh` 或将令牌保存到 `~/.claude/.secrets`

> **注意：** 免费版每月有文档页数配额。具体限制请查看 [mineru.net](https://mineru.net) 最新信息。

## 如何验证 Hook 是否触发

```bash
# 查看事件日志
cat ~/.claude/mineru-cache/hook.log

# 示例输出：
# {"ts":"2026-06-04T19:52:47Z","event":"convert_start","file":"report.pdf","detail":"size=1.4MB ext=.pdf"}
# {"ts":"2026-06-04T19:52:58Z","event":"convert_done","file":"report.pdf","detail":"elapsed=11.1s md_size=8984B"}

# 查看已缓存的转换结果
ls -lh ~/.claude/mineru-cache/*.md
```

**日志事件：**

| 事件 | 含义 |
|-------|---------|
| `convert_start` | Hook 已触发，正在上传到 MinerU |
| `convert_done` | 转换完成，已缓存 |
| `cache_hit` | 文件已转换过，即时重定向 |
| `convert_error` | 转换失败（查看 detail 字段了解原因） |
| `skip_no_key` | API Key 未配置 |

## 工作原理

1. **PreToolUse Hook** 拦截每一次 `Read` 工具调用
2. 检查文件扩展名是否在可转换列表中（`.pdf`、`.docx`、`.pptx`、`.xlsx` 等）
3. 跳过图片文件（`.png`、`.jpg` 等）—— 这些由 `ai-vision-hook` 处理
4. 检查缓存（`~/.claude/mineru-cache/{md5}.md`）—— 有效则即时返回
5. 上传到 MinerU API，轮询等待处理完成（最长 7.5 分钟超时）
6. 下载结果 zip，提取 `full.md`，缓存到本地
7. **重定向** Read 到缓存的 Markdown —— 模型只看到干净的格式化文本

## 文件结构

```
mineru-auto-hook/
├── mineru-auto-hook.py   # 主 Hook 脚本（Python 3，仅用标准库）
├── setup.sh               # 一键交互式安装脚本
├── .gitignore
├── README.md              # 英文文档
└── README_ZH.md           # 中文文档（本文件）
```

## 环境要求

- **Python 3.9+**（仅用标准库，无需 pip 安装任何依赖）
- **unzip**（macOS/Linux 预装）
- **Claude Code** 需启用 Hooks
- **MinerU API Key**（在 [mineru.net](https://mineru.net) 免费注册获取）

## 致谢

- **[MinerU](https://github.com/opendatalab/MinerU)** — OpenDataLab 开源文档解析引擎
- **[mineru-mcp](https://github.com/opendatalab/MinerU)** — 本 Hook 的灵感来源
- **[mineru.net](https://mineru.net)** — OpenXLab 提供的云 API 服务

## 许可证

MIT — 随便用，随便改，随便发。
