# Changelog

## v0.2.0 — SketchyBar integration & runner architecture

### New
- **Runner-based dispatch** — instances use `runner:` field; `yb.sh` delegates to modular scripts in `runners/`
- **`runners/bar.sh`** — full sketchybar orchestrator with probe-based display discovery and space binding
- **`runners/tile.sh`** — repositions existing Code + Terminal windows (used on workspace switch)
- **Probe-based display targeting** — sketchybar display index resolved via bounding_rects + CG coordinate matching; no fragile index assumptions
- **Space-aware items** — bar items bound to specific Mission Control desktop via `associated_space` (UUID + plist global index)
- **Standard bar redesign** — left: [YB] badge + workspace name + path; right: action icons (Code, Terminal, Folder, Close) with hover highlight
- **Nerd Font icons** — Hack Nerd Font with python3 unicode generation (bash 3.2 compatible)
- **Icon hover plugin** — `sketchybar/plugins/icon_hover.sh` for mouse.entered/mouse.exited effects
- **Workspace switching** — detects open workspace via `code --status`, re-tiles + updates bar instead of recreating
- **README.md** — full project documentation

### Changed
- Instance YAML format: `runner: split` replaces `type:` reference; `bar:`, `gap:`, `padding:` defined directly
- Renamed instances: `mermaid` → `mm`, `yb-dev` → `dev`, `claude-task` → `ai`, `styk-main` → `styk`
- Legacy type path now uses `bar.sh` runner (probe + associated_space) instead of direct script call
- `sketchybar/sketchybarrc` emptied — all configuration from `bar.sh` to prevent label overwrite
- `sketchybar/bars/minimal.sh` — added path display, disabled script/updates to prevent overwrites
- `sketchybar/bars/standard.sh` — complete rewrite with badge + name + path + 4 action icons

### Removed
- `run-iterm.sh` — moved diagnostic to `runners/iterm.sh`
- Old instance files (`mermaid.yaml`, `yb-dev.yaml`, `claude-task.yaml`, `styk-main.yaml`)

## v0.1.0 — Initial release

- Working orchestrator with Terminal.app fallback
- Tile, splitview, and BSP modes
- SketchyBar basic integration
- Virtual desktop creation via Mission Control automation
