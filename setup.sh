#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# MinerU Auto-Convert Hook — One-Click Setup
#
# Installs the hook script, configures Claude Code,
# and sets up the MinerU API key.
#
# Usage:
#   bash setup.sh
# ──────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"
CACHE_DIR="${CLAUDE_DIR}/mineru-cache"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  MinerU Auto-Convert Hook — Setup${RESET}"
echo -e "${BOLD}  Based on mineru-mcp (github.com/opendatalab/MinerU)${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ── Step 1: Copy hook script ──────────────────────────────
echo -e "${BOLD}[1/5]${RESET} Installing hook script..."

mkdir -p "${SCRIPTS_DIR}"

if [[ -f "${SCRIPTS_DIR}/mineru-auto-hook.py" ]]; then
    echo -e "  ${YELLOW}⚠${RESET}  ${SCRIPTS_DIR}/mineru-auto-hook.py already exists"
    read -rp "     Overwrite? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        cp "${SCRIPT_DIR}/mineru-auto-hook.py" "${SCRIPTS_DIR}/mineru-auto-hook.py"
        echo -e "  ${GREEN}✓${RESET} Updated"
    else
        echo -e "  ${YELLOW}○${RESET} Skipped (existing file kept)"
    fi
else
    cp "${SCRIPT_DIR}/mineru-auto-hook.py" "${SCRIPTS_DIR}/mineru-auto-hook.py"
    echo -e "  ${GREEN}✓${RESET} Installed → ${SCRIPTS_DIR}/mineru-auto-hook.py"
fi

# ── Step 2: API Key ───────────────────────────────────────
echo -e "${BOLD}[2/4]${RESET} Configuring MinerU API key..."
echo ""
echo -e "  MinerU API key 获取方式:"
echo -e "  1. 访问 ${BOLD}https://mineru.net${RESET} 注册账号"
echo -e "  2. 进入控制台 → API 管理 → 创建 API Key"
echo -e "  3. 复制 JWT 格式的 API Key"
echo ""

SECRETS_FILE="${CLAUDE_DIR}/.secrets"

if [[ -f "${SECRETS_FILE}" ]] && grep -q "MINERU_API_KEY=" "${SECRETS_FILE}" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${RESET}  MINERU_API_KEY already set in ${SECRETS_FILE}"
    read -rp "     Update? [y/N] " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        echo -e "  ${YELLOW}○${RESET} Skipped"
    else
        read -rsp "     Paste your MinerU API Key: " api_key
        echo ""
        if [[ -n "$api_key" ]]; then
            if grep -q "MINERU_API_KEY=" "${SECRETS_FILE}" 2>/dev/null; then
                if command -v gsed &>/dev/null; then
                    gsed -i '' "s|MINERU_API_KEY=.*|MINERU_API_KEY=${api_key}|" "${SECRETS_FILE}"
                else
                    sed -i '' "s|MINERU_API_KEY=.*|MINERU_API_KEY=${api_key}|" "${SECRETS_FILE}"
                fi
            fi
            chmod 600 "${SECRETS_FILE}"
            echo -e "  ${GREEN}✓${RESET} Updated"
        fi
    fi
else
    read -rsp "     Paste your MinerU API Key (input hidden): " api_key
    echo ""
    if [[ -n "$api_key" ]]; then
        cat > "${SECRETS_FILE}" << EOF
# WARNING: This file contains secrets. DO NOT commit, share, or copy.
# Permissions: chmod 600 — owner read/write only.
MINERU_API_KEY=${api_key}
EOF
        chmod 600 "${SECRETS_FILE}"
        echo -e "  ${GREEN}✓${RESET} Saved → ${SECRETS_FILE} (chmod 600)"
    else
        echo -e "  ${YELLOW}○${RESET} Skipped (no key entered). Set later: echo 'MINERU_API_KEY=...' >> ${SECRETS_FILE}"
    fi
fi

# ── Step 3: Cache directory ───────────────────────────────
echo -e "${BOLD}[3/4]${RESET} Creating cache directory..."
mkdir -p "${CACHE_DIR}"
echo -e "  ${GREEN}✓${RESET} Created → ${CACHE_DIR}"

# ── Step 4: Hook configuration ────────────────────────────
echo -e "${BOLD}[4/4]${RESET} Configuring Claude Code hook..."

if [[ ! -f "${SETTINGS_FILE}" ]]; then
    echo -e "  ${RED}✗${RESET} ${SETTINGS_FILE} not found. Is Claude Code installed?"
    echo ""
    echo "  Manual configuration — add to ~/.claude/settings.json:"
    echo ""
    echo '  "hooks": {'
    echo '    "PreToolUse": ['
    echo '      {'
    echo '        "matcher": "Read",'
    echo '        "hooks": ['
    echo '          {'
    echo '            "type": "command",'
    echo '            "command": "python3 '"${SCRIPTS_DIR}"'/mineru-auto-hook.py",'
    echo '            "timeout": 600'
    echo '          }'
    echo '        ]'
    echo '      }'
    echo '    ]'
    echo '  }'
    exit 0
fi

# Check if hook already configured
if python3 -c "
import json, sys
try:
    with open('${SETTINGS_FILE}') as f:
        cfg = json.load(f)
    hooks = cfg.get('hooks', {}).get('PreToolUse', [])
    for h in hooks:
        for hh in h.get('hooks', []):
            if 'mineru-auto-hook' in hh.get('command', ''):
                sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null; then
    echo -e "  ${YELLOW}○${RESET} Hook already configured in settings.json"
else
    echo -e "  ${YELLOW}!${RESET}  Hook not yet in settings.json."
    echo ""
    echo -e "  ${BOLD}Add to ~/.claude/settings.json:${RESET}"
    echo ""
    echo '  In "hooks" → "PreToolUse", add or merge into the "Read" matcher:'
    echo ""
    echo '  {'
    echo '    "type": "command",'
    echo '    "command": "python3 '"${SCRIPTS_DIR}"'/mineru-auto-hook.py",'
    echo '    "timeout": 600'
    echo '  }'
    echo ""
    echo -e "  ${YELLOW}See README.md for detailed instructions.${RESET}"
fi

# ── Done ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  Setup complete!${RESET}"
echo ""
echo -e "  ${BOLD}How to verify:${RESET}"
echo -e "  1. Place a PDF/DOCX/PPTX/XLSX file in any project"
echo -e "  2. Ask Claude to read it → hook auto-converts to markdown"
echo -e "  3. Check log:  ${BOLD}cat ${CACHE_DIR}/hook.log${RESET}"
echo -e "  4. Check cache: ${BOLD}ls ${CACHE_DIR}/*.md${RESET}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
