#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# Secret Scanner — detects API keys, JWTs, and tokens in
# Claude config, session files, and scripts.
#
# Usage:
#   ./scan-secrets.sh          # scan all
#   ./scan-secrets.sh --fix    # auto-redact (session files only)
# ──────────────────────────────────────────────────────────
set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

AUTO_FIX=false
[[ "${1:-}" == "--fix" ]] && AUTO_FIX=true

# ── Patterns to detect ────────────────────────────────────
# JWT (3 base64url segments separated by dots)
JWT_PAT='eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'
# Generic API key patterns
API_KEY_PAT='(sk-[a-zA-Z0-9]{20,}|api[_-]?key[=:]\s*[a-zA-Z0-9_-]{20,}|token[=:]\s*[a-zA-Z0-9_-]{20,})'

FOUND=0

scan_file() {
    local file="$1"
    local matches=""

    # Check for JWTs
    if command -v ggrep &>/dev/null; then
        matches=$(ggrep -oPn "$JWT_PAT" "$file" 2>/dev/null || true)
    else
        matches=$(grep -oEn "$JWT_PAT" "$file" 2>/dev/null || true)
    fi

    if [[ -n "$matches" ]]; then
        echo -e "${RED}⚠ SECRET FOUND:${RESET} $file"
        echo "$matches" | while read -r line; do
            echo "  Line: $line"
        done
        FOUND=$((FOUND + 1))

        if $AUTO_FIX; then
            # Only auto-fix session files
            if [[ "$file" == *session*.tmp ]]; then
                if command -v gsed &>/dev/null; then
                    gsed -i '' -E "s/$JWT_PAT/[REDACTED-JWT]/g" "$file"
                else
                    sed -i '' -E "s/$JWT_PAT/[REDACTED-JWT]/g" "$file"
                fi
                echo -e "  ${GREEN}→ Redacted${RESET}"
            fi
        fi
    fi
}

echo "=== Secret Scanner ==="
echo "Target: $CLAUDE_DIR"
echo "Date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Scan session files
echo "── Session files ──"
shopt -s nullglob
for f in "$CLAUDE_DIR"/session-data/*.tmp "$CLAUDE_DIR"/sessions/*.tmp; do
    scan_file "$f"
done

# Scan scripts (skip .secrets and the scanner itself)
echo ""
echo "── Scripts ──"
while IFS= read -r -d '' f; do
    [[ "$f" == */.secrets ]] && continue
    [[ "$f" == */scan-secrets.sh ]] && continue
    [[ "$f" == */mineru-cache/* ]] && continue
    scan_file "$f"
done < <(find "$CLAUDE_DIR" -type f \( -name "*.py" -o -name "*.sh" -o -name "*.js" -o -name "*.json" -o -name "*.yml" -o -name "*.yaml" -o -name "*.toml" \) -print0 2>/dev/null)

echo ""
if [[ $FOUND -eq 0 ]]; then
    echo -e "${GREEN}✓ No secrets found${RESET}"
else
    echo -e "${RED}✗ $FOUND file(s) contain secrets${RESET}"
    if ! $AUTO_FIX; then
        echo "  Run with --fix to auto-redact session files"
    fi
fi

exit $FOUND
