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

# read from /dev/tty so it works under curl | bash
prompt() { read -rp "$1" "$2" < /dev/tty; }

usage() {
  cat <<EOF
Usage: ./install.sh [OPTIONS]

Install the travel-planner skill for Claude Code or Codex.

Agent (default: claude):
  --claude            Target Claude Code
  --codex             Target Codex

Scope (default: interactive):
  -p, --project       Install to current project scope
  -u, --user          Install to user scope

Other:
  --skip-deps         Skip dependency checks
  --update            Update skill files (auto-detect installed scopes)
  --doctor            Check skill installation and dependency status
  -h, --help          Show this help

Examples:
  ./install.sh                        # interactive
  ./install.sh --user                 # Claude Code, user scope
  ./install.sh --codex --project      # Codex, project scope
  ./install.sh --update               # update all installed copies
EOF
  exit 0
}

# ─── Parse Args ───
AGENT=""
SCOPE=""
SKIP_DEPS=false
DOCTOR=false
UPDATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude)     AGENT="claude"; shift ;;
    --codex)      AGENT="codex"; shift ;;
    -p|--project) SCOPE="project"; shift ;;
    -u|--user)    SCOPE="user"; shift ;;
    --skip-deps)  SKIP_DEPS=true; shift ;;
    --update)     UPDATE=true; shift ;;
    --doctor)     DOCTOR=true; shift ;;
    -h|--help)    usage ;;
    *) err "Unknown option: $1"; usage ;;
  esac
done

# ─── Agent Selection ───
select_agent() {
  if [[ -n "$AGENT" ]]; then
    return
  fi

  printf "\n  Select agent:\n"
  printf "    ${CYAN}1)${NC} Claude Code\n"
  printf "    ${CYAN}2)${NC} Codex\n\n"

  while true; do
    prompt "  Agent [1/2]: " choice
    case "$choice" in
      1) AGENT="claude"; return ;;
      2) AGENT="codex"; return ;;
      *) warn "Please enter 1 or 2" ;;
    esac
  done
}

# ─── Scope Selection ───
select_scope() {
  if [[ -n "$SCOPE" ]]; then
    return
  fi

  local base_dir
  case "$AGENT" in
    claude) base_dir=".claude" ;;
    codex)  base_dir=".codex" ;;
  esac

  printf "\n  Select scope:\n"
  printf "    ${CYAN}1)${NC} project — Current directory ${DIM}($(pwd)/${base_dir}/skills/)${NC}\n"
  printf "    ${CYAN}2)${NC} user    — All projects ${DIM}(~/${base_dir}/skills/)${NC}\n\n"

  while true; do
    prompt "  Scope [1/2]: " choice
    case "$choice" in
      1) SCOPE="project"; return ;;
      2) SCOPE="user"; return ;;
      *) warn "Please enter 1 or 2" ;;
    esac
  done
}

get_target_dir() {
  local base_dir
  case "$AGENT" in
    claude) base_dir=".claude" ;;
    codex)  base_dir=".codex" ;;
  esac

  case "$SCOPE" in
    project) echo "$(pwd)/${base_dir}/skills/${SKILL_NAME}" ;;
    user)    echo "${HOME}/${base_dir}/skills/${SKILL_NAME}" ;;
  esac
}

# ─── Install Skill ───
copy_skill_to() {
  local target="$1"
  mkdir -p "${target}/assets"
  cp "${SCRIPT_DIR}/skill.md"              "${target}/skill.md"
  cp "${SCRIPT_DIR}/assets/template.html"  "${target}/assets/template.html"
  cp "${SCRIPT_DIR}/assets/preview.html"   "${target}/assets/preview.html"
  cp "${SCRIPT_DIR}/assets/generate.py"    "${target}/assets/generate.py"
}

install_skill() {
  local target
  target="$(get_target_dir)"
  info "Installing to ${SCOPE} scope: ${target}"
  copy_skill_to "${target}"
  ok "Skill files installed"
}

# ─── Update ───
run_update() {
  printf "\n  ${BOLD}╔══════════════════════════════════════╗${NC}\n"
  printf "  ${BOLD}║   Travel Planner — Update            ║${NC}\n"
  printf "  ${BOLD}╚══════════════════════════════════════╝${NC}\n\n"

  local updated=0
  for dir in \
    "$(pwd)/.claude/skills/${SKILL_NAME}" \
    "${HOME}/.claude/skills/${SKILL_NAME}" \
    "$(pwd)/.codex/skills/${SKILL_NAME}" \
    "${HOME}/.codex/skills/${SKILL_NAME}"; do
    if [[ -f "${dir}/skill.md" ]]; then
      copy_skill_to "${dir}"
      ok "Updated: ${dir}"
      updated=$((updated + 1))
    fi
  done

  if [[ $updated -eq 0 ]]; then
    warn "No existing installation found. Run ./install.sh to install first."
  else
    printf "\n  ${GREEN}${updated}${NC} installation(s) updated.\n"
  fi
  printf "\n"
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
  printf "        ${DIM}https://github.com/alibaba-flyai/flyai-skill${NC}\n\n"

  if docker_running flyai; then
    ok "Found (docker)"; record flyai ok; return
  fi
  if has_cmd flyai; then
    ok "Found ($(command -v flyai))"; record flyai ok; return
  fi

  warn "Not found"
  printf "\n    ${YELLOW}Fallback:${NC} web search for travel data (no real-time pricing)\n\n"
  printf "    Install options:\n"
  printf "      ${CYAN}1)${NC} npm i -g @fly-ai/flyai-cli\n"
  printf "      ${CYAN}2)${NC} Claude Code plugin (via /plugin command)\n"
  printf "      ${CYAN}s)${NC} Skip — use web search fallback\n\n"

  prompt "    Choice [1/2/s]: " choice
  case "$choice" in
    1)
      info "Running: npm i -g @fly-ai/flyai-cli"
      if npm i -g @fly-ai/flyai-cli; then ok "flyai-cli installed"; record flyai ok
      else err "Install failed"; record flyai failed; fi
      ;;
    2)
      info "Run these in Claude Code:"
      printf "      ${DIM}/plugin marketplace add alibaba-flyai/flyai-skill${NC}\n"
      printf "      ${DIM}/plugin install flyai@alibaba-flyai-flyai-skill${NC}\n"
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

  prompt "    Choice [1/2/s]: " choice
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
  printf "        ${DIM}https://github.com/GuDaStudio/GrokSearch (branch: grok-with-tavily)${NC}\n\n"

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

  prompt "    Choice [1/2/s]: " choice
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

# ─── Doctor Mode ───
doctor_check() {
  local name="$1" desc="$2" fallback="$3"
  shift 3
  # remaining args are check commands (any passing = ok)
  local found=false method=""

  for check in "$@"; do
    if eval "$check" &>/dev/null; then
      found=true
      method="$check"
      break
    fi
  done

  if $found; then
    printf "    ${GREEN}✓${NC} %-20s %s\n" "$name" "$desc"
    return 0
  else
    printf "    ${RED}✗${NC} %-20s %s\n" "$name" "${desc} ${DIM}— fallback: ${fallback}${NC}"
    return 1
  fi
}

run_doctor() {
  printf "\n  ${BOLD}╔══════════════════════════════════════╗${NC}\n"
  printf "  ${BOLD}║    Travel Planner — Doctor Check     ║${NC}\n"
  printf "  ${BOLD}╚══════════════════════════════════════╝${NC}\n"

  # ── Skill Installation ──
  printf "\n  ${BOLD}Skill${NC}\n"

  local found_any=false
  for dir in \
    "$(pwd)/.claude/skills/${SKILL_NAME}" \
    "${HOME}/.claude/skills/${SKILL_NAME}" \
    "$(pwd)/.codex/skills/${SKILL_NAME}" \
    "${HOME}/.codex/skills/${SKILL_NAME}"; do
    if [[ -f "${dir}/skill.md" ]]; then
      found_any=true
      printf "    ${GREEN}✓${NC} %s\n" "${dir}"
      for f in template.html preview.html generate.py; do
        if [[ -f "${dir}/assets/${f}" ]]; then
          printf "      ${GREEN}✓${NC} assets/${f}\n"
        else
          printf "      ${RED}✗${NC} assets/${f} ${DIM}missing${NC}\n"
        fi
      done
    fi
  done

  if ! $found_any; then
    printf "    ${RED}✗${NC} Not installed in any scope\n"
    printf "      ${DIM}Run ./install.sh to install${NC}\n"
  fi

  # ── Dependencies ──
  printf "\n  ${BOLD}Dependencies${NC}\n"

  local total=0 passed=0

  total=$((total + 1))
  if doctor_check \
    "flyai" \
    "飞猪实时数据 (机票/酒店/门票)" \
    "web search" \
    "docker_running flyai" \
    "has_cmd flyai"; then
    passed=$((passed + 1))
  fi

  total=$((total + 1))
  if doctor_check \
    "mcporter" \
    "小红书 CLI" \
    "site:xiaohongshu.com" \
    "has_cmd mcporter"; then
    passed=$((passed + 1))
  fi

  total=$((total + 1))
  if doctor_check \
    "xiaohongshu MCP" \
    "小红书 MCP server (port 18060)" \
    "site:xiaohongshu.com" \
    "docker_running 'xiaohongshu\|xhs'" \
    "port_open 18060"; then
    passed=$((passed + 1))
  fi

  total=$((total + 1))
  if doctor_check \
    "grok-search" \
    "网络搜索 MCP" \
    "built-in WebSearch" \
    "docker_running grok"; then
    passed=$((passed + 1))
  fi

  # ── Docker Services ──
  printf "\n  ${BOLD}Docker${NC}\n"
  if has_cmd docker && docker info &>/dev/null; then
    printf "    ${GREEN}✓${NC} Docker daemon running\n"
    local containers
    containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'flyai|mcporter|xiaohongshu|xhs|grok' || true)
    if [[ -n "$containers" ]]; then
      printf "    ${GREEN}✓${NC} Related containers:\n"
      while IFS= read -r name; do
        printf "      ${DIM}•${NC} %s\n" "$name"
      done <<< "$containers"
    else
      printf "    ${DIM}–${NC} No related containers running\n"
      printf "      ${DIM}docker ps | grep -iE 'flyai|mcporter|xiaohongshu|xhs|grok'${NC}\n"
    fi
  else
    printf "    ${DIM}–${NC} Docker not available\n"
  fi

  # ── Summary ──
  printf "\n  ${BOLD}──────────────────────────────────${NC}\n"
  if $found_any && [[ $passed -eq $total ]]; then
    printf "  ${GREEN}All good!${NC} Skill installed, ${passed}/${total} deps available.\n"
  elif $found_any; then
    printf "  Skill installed. ${GREEN}${passed}${NC}/${total} deps available.\n"
    printf "  ${DIM}Missing deps have automatic fallbacks — skill still works.${NC}\n"
    printf "  ${DIM}Run ./install.sh to install missing dependencies.${NC}\n"
  else
    printf "  ${RED}Skill not installed.${NC} Run ${BOLD}./install.sh${NC} first.\n"
  fi
  printf "\n"
}

# ─── Main ───
main() {
  if $DOCTOR; then
    run_doctor
    return
  fi

  if $UPDATE; then
    run_update
    return
  fi

  printf "\n  ${BOLD}╔══════════════════════════════════════╗${NC}\n"
  printf "  ${BOLD}║   Travel Planner — Skill Installer   ║${NC}\n"
  printf "  ${BOLD}╚══════════════════════════════════════╝${NC}\n"

  select_agent
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
