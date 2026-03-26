# Travel Planner Skill

Claude Code skill，生成详细的多日旅行计划 HTML 页面。

涵盖天气预报、每日行程（景点+交通）、餐饮推荐、酒店住宿对比、详细预算。通过多源网络搜索（含小红书真实用户反馈）采集信息。

## Install

One-liner (no clone needed):

```bash
# Interactive — asks scope + dependencies
curl -fsSL https://raw.githubusercontent.com/tianxingyang/skills-travel-planner/main/setup.sh | bash

# Specify agent + scope directly
curl -fsSL https://raw.githubusercontent.com/tianxingyang/skills-travel-planner/main/setup.sh | bash -s -- --user              # Claude Code, user
curl -fsSL https://raw.githubusercontent.com/tianxingyang/skills-travel-planner/main/setup.sh | bash -s -- --codex --user      # Codex, user
curl -fsSL https://raw.githubusercontent.com/tianxingyang/skills-travel-planner/main/setup.sh | bash -s -- --codex --project   # Codex, project

# Skip dependency prompts
curl -fsSL https://raw.githubusercontent.com/tianxingyang/skills-travel-planner/main/setup.sh | bash -s -- --user --skip-deps
```

Or clone and run locally:

```bash
git clone git@github.com:tianxingyang/skills-travel-planner.git
cd skills-travel-planner && ./install.sh
```

## Dependencies

All optional — each has a built-in fallback via web search.

| Dependency | Purpose | Fallback |
|---|---|---|
| **flyai** | 飞猪实时数据（机票/酒店/门票） | web search (no real-time pricing) |
| **mcporter** + 小红书 MCP | 小红书笔记搜索 | `site:xiaohongshu.com` web search |
| **grok-search** MCP | 网络搜索 + 网页抓取 | built-in WebSearch / WebFetch |

Diagnose installation status:

```bash
# Local
./install.sh --doctor

# Remote
curl -fsSL https://raw.githubusercontent.com/tianxingyang/skills-travel-planner/main/setup.sh | bash -s -- --doctor
```

## Structure

```
skill.md              ← skill definition
assets/
  template.html       ← fallback HTML template
  preview.html        ← demo preview (京都5日游)
  generate.py         ← tripData.json → HTML generator
install.sh            ← installer script
```

## Usage

安装后在 Claude Code / Codex 中触发关键词：旅行计划、旅游攻略、出行规划、行程安排、去哪里玩、目的地推荐 等。

即使只说了时间和人员但不确定目的地，也会进入推荐流程。
