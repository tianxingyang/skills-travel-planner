#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="travel-planner"

# ─── Colors ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$1"; }
info() { printf "  ${CYAN}→${NC} %s\n" "$1"; }

usage() {
  cat <<EOF
Usage: ./install.sh [OPTIONS]

Install the travel-planner skill for Claude Code.

Options:
  -p, --project     Install to current project scope (./.claude/skills/)
  -u, --user        Install to user scope (~/.claude/skills/)
  --skip-deps       Skip dependency checks
  -h, --help        Show this help

If no scope is specified, the script will ask interactively.
EOF
  exit 0
}

# ─── Parse Args ───
SCOPE=""
SKIP_DEPS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) SCOPE="project"; shift ;;
    -u|--user)    SCOPE="user"; shift ;;
    --skip-deps)  SKIP_DEPS=true; shift ;;
    -h|--help)    usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

# ─── Scope Selection ───
select_scope() {
  if [[ -n "$SCOPE" ]]; then
    return
  fi

  printf "\n  Select installation scope:\n"
  printf "    ${CYAN}1)${NC} project — Current directory only ${DIM}($(pwd))${NC}\n"
  printf "    ${CYAN}2)${NC} user    — All projects ${DIM}(~/.claude/skills/)${NC}\n\n"

  while true; do
    read -rp "  Choice [1/2]: " choice
    case "$choice" in
      1) SCOPE="project"; return ;;
      2) SCOPE="user"; return ;;
      *) warn "Please enter 1 or 2" ;;
    esac
  done
}

get_target_dir() {
  case "$SCOPE" in
    project) echo "$(pwd)/.claude/skills/${SKILL_NAME}" ;;
    user)    echo "${HOME}/.claude/skills/${SKILL_NAME}" ;;
  esac
}

# ─── Install Skill ───
install_skill() {
  local target
  target="$(get_target_dir)"

  info "Installing to ${SCOPE} scope: ${target}"

  mkdir -p "${target}/assets"
  cp "${SCRIPT_DIR}/skill.md"              "${target}/skill.md"
  cp "${SCRIPT_DIR}/assets/template.html"  "${target}/assets/template.html"
  cp "${SCRIPT_DIR}/assets/preview.html"   "${target}/assets/preview.html"
  cp "${SCRIPT_DIR}/assets/generate.py"    "${target}/assets/generate.py"

  ok "Skill files installed"
}

# ─── Dependency Helpers ───
docker_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "$1"
}

has_cmd() {
  command -v "$1" &>/dev/null
}

port_open() {
  (echo > /dev/tcp/localhost/"$1") 2>/dev/null
}

# Track results: name:status
DEP_STATUS=()
record() { DEP_STATUS+=("$1:$2"); }

# ─── [1/3] flyai ───
check_flyai() {
  printf "\n  ${BOLD}[1/3] flyai${NC} — 飞猪实时数据（机票 / 酒店 / 景点门票）\n"
  printf "        ${DIM}Provides real-time pricing from Fliggy (Alibaba Travel)${NC}\n\n"

  if docker_running flyai; then
    ok "Found (docker)"; record flyai ok; return
  fi
  if has_cmd flyai; then
    ok "Found ($(command -v flyai))"; record flyai ok; return
  fi

  warn "Not found"
  printf "\n    ${YELLOW}Fallback:${NC} web search for travel data (no real-time pricing)\n\n"
  printf "    Install options:\n"
  printf "      ${CYAN}1)${NC} npm install -g flyai\n"
  printf "      ${CYAN}2)${NC} Claude Code plugin (add to settings.json)\n"
  printf "      ${CYAN}s)${NC} Skip — use web search fallback\n\n"

  read -rp "    Choice [1/2/s]: " choice
  case "$choice" in
    1)
      info "Running: npm install -g flyai"
      if npm install -g flyai; then ok "flyai installed"; record flyai ok
      else err "Install failed"; record flyai failed; fi
      ;;
    2)
      info "Add to your .claude/settings.json:"
      printf '    {"enabledPlugins": {"flyai@flyai-marketplace": true}}\n'
      record flyai manual
      ;;
    *)
      info "Skipped"; record flyai skipped ;;
  esac
}

# ─── [2/3] mcporter + xiaohongshu MCP ───
check_mcporter() {
  printf "\n  ${BOLD}[2/3] mcporter + 小红书 MCP${NC} — 小红书笔记搜索（真实用户反馈）\n"
  printf "        ${DIM}mcporter CLI → xiaohongshu MCP server (port 18060)${NC}\n\n"

  # Check mcporter CLI
  local cli_ok=false mcp_ok=false

  if has_cmd mcporter; then
    ok "mcporter CLI found"; cli_ok=true
  fi

  # Check xiaohongshu MCP (docker or port)
  if docker_running 'xiaohongshu\|xhs'; then
    ok "小红书 MCP found (docker)"; mcp_ok=true
  elif port_open 18060; then
    ok "小红书 MCP found (port 18060)"; mcp_ok=true
  fi

  if $cli_ok && $mcp_ok; then
    record mcporter ok; return
  fi

  # Show what's missing
  if ! $cli_ok; then warn "mcporter CLI not found"; fi
  if ! $mcp_ok; then warn "小红书 MCP server not found"; fi

  printf "\n    ${YELLOW}Fallback:${NC} web search with site:xiaohongshu.com (limited)\n\n"
  printf "    Docker check command:\n"
  printf "      ${DIM}docker ps | grep -iE 'mcporter|xiaohongshu|xhs'${NC}\n\n"
  printf "    Install options:\n"
  printf "      ${CYAN}1)${NC} npm install (mcporter CLI + 小红书 MCP)\n"
  printf "      ${CYAN}2)${NC} Docker compose (if you have a compose file)\n"
  printf "      ${CYAN}s)${NC} Skip — use web search fallback\n\n"

  read -rp "    Choice [1/2/s]: " choice
  case "$choice" in
    1)
      if ! $cli_ok; then
        info "Running: npm install -g mcporter"
        if npm install -g mcporter; then ok "mcporter installed"
        else err "mcporter install failed"; fi
      fi
      if ! $mcp_ok; then
        info "Running: npm install -g xiaohongshu-mcp"
        if npm install -g xiaohongshu-mcp; then
          ok "xiaohongshu-mcp installed"
          info "Start with: xiaohongshu-mcp --port 18060"
        else err "xiaohongshu-mcp install failed"; fi
      fi
      record mcporter manual
      ;;
    2)
      info "Start your docker compose with xiaohongshu MCP service"
      info "Ensure port 18060 is exposed"
      record mcporter manual
      ;;
    *)
      info "Skipped"; record mcporter skipped ;;
  esac
}

# ─── [3/3] grok-search ───
check_grok_search() {
  printf "\n  ${BOLD}[3/3] grok-search MCP${NC} — 网络搜索（通用信息检索）\n"
  printf "        ${DIM}Powers web_search / web_fetch for real-time info${NC}\n\n"

  if docker_running grok; then
    ok "Found (docker)"; record grok ok; return
  fi

  warn "Not found"
  printf "\n    ${YELLOW}Fallback:${NC} Built-in WebSearch / WebFetch tools\n\n"
  printf "    Docker check command:\n"
  printf "      ${DIM}docker ps | grep -i grok${NC}\n\n"
  printf "    Install options:\n"
  printf "      ${CYAN}1)${NC} npm install (grok-search MCP server)\n"
  printf "      ${CYAN}2)${NC} Configure manually in .mcp.json\n"
  printf "      ${CYAN}s)${NC} Skip — use built-in WebSearch\n\n"

  read -rp "    Choice [1/2/s]: " choice
  case "$choice" in
    1)
      info "Running: npm install -g grok-search-mcp"
      if npm install -g grok-search-mcp; then
        ok "grok-search-mcp installed"
        info "Add to your .mcp.json to activate"
      else err "Install failed"; fi
      record grok manual
      ;;
    2)
      info "Add grok-search to your .mcp.json:"
      cat <<'SAMPLE'
    {
      "mcpServers": {
        "grok-search": {
          "command": "grok-search-mcp",
          "args": ["--port", "3100"]
        }
      }
    }
SAMPLE
      record grok manual
      ;;
    *)
      info "Skipped"; record grok skipped ;;
  esac
}

# ─── Summary ───
print_summary() {
  local target
  target="$(get_target_dir)"

  printf "\n  ${BOLD}══════════════════════════════════${NC}\n"
  printf "  ${BOLD}  Installation Complete${NC}\n"
  printf "  ${BOLD}══════════════════════════════════${NC}\n\n"

  ok "Skill: ${target}"
  printf "\n  Dependencies:\n"

  for entry in "${DEP_STATUS[@]}"; do
    local name="${entry%%:*}" status="${entry##*:}"
    case "$status" in
      ok)      printf "    ${GREEN}✓${NC} ${name}\n" ;;
      manual)  printf "    ${YELLOW}!${NC} ${name} ${DIM}(manual setup needed)${NC}\n" ;;
      skipped) printf "    ${DIM}–${NC} ${name} ${DIM}(skipped, using fallback)${NC}\n" ;;
      failed)  printf "    ${RED}✗${NC} ${name} ${DIM}(install failed)${NC}\n" ;;
    esac
  done

  printf "\n  ${CYAN}Restart Claude Code to activate the skill.${NC}\n"

  # Fallback reminder
  local has_skipped=false
  for entry in "${DEP_STATUS[@]}"; do
    [[ "${entry##*:}" == "skipped" ]] && has_skipped=true
  done
  if $has_skipped; then
    printf "\n  ${DIM}Skipped dependencies have automatic fallbacks:${NC}\n"
    printf "  ${DIM}  flyai     → web search (no real-time pricing)${NC}\n"
    printf "  ${DIM}  mcporter  → site:xiaohongshu.com search${NC}\n"
    printf "  ${DIM}  grok      → built-in WebSearch/WebFetch${NC}\n"
  fi
  printf "\n"
}

# ─── Main ───
main() {
  printf "\n  ${BOLD}╔══════════════════════════════════════╗${NC}\n"
  printf "  ${BOLD}║   Travel Planner — Skill Installer   ║${NC}\n"
  printf "  ${BOLD}╚══════════════════════════════════════╝${NC}\n"

  select_scope
  install_skill

  if $SKIP_DEPS; then
    info "Dependency checks skipped (--skip-deps)"
    printf "\n"
    return
  fi

  printf "\n  ${BOLD}── Optional Dependencies ──${NC}\n"
  printf "  ${DIM}Each has a fallback — all are optional.${NC}\n"

  check_flyai
  check_mcporter
  check_grok_search
  print_summary
}

main
