# Changelog

## v0.4.0 — Architecture: separate terminal from layout + shared library

### New
- **`lib/common.sh`** — shared library with window finding, positioning, display geometry, and close functions; yabai-first with JXA fallback handled internally
- **`lib/display_frame.jxa`** — standalone JXA script for display geometry when yabai unavailable
- **`terminal:` field** — layouts and instances specify which terminal to open: `iterm` (default), `terminal`, or `none`
- **`mode:` field** — replaces `runner:` for layout mode: `tile`, `solo`, `splitview`
- **`layout:` field** — replaces `type:` in instances; references `layouts/*.yaml`
- **iTerm2 as default** — all layouts and standalone instances default to iTerm2

### Changed
- **Renamed `types/` → `layouts/`** — reflects actual purpose (workspace templates, not types)
- **Runners are layout-only** — `tile.sh` and `solo.sh` only find and position windows; app opening moved to `yb.sh`
- **`runners/tile.sh`** — rewritten from 316 → 69 lines using `lib/common.sh`
- **`runners/solo.sh`** — rewritten from 93 → 62 lines using `lib/common.sh`
- **`yb.sh`** — rewritten: unified resolution (layout + instance), inline app opening, layout runner dispatch, library-based close; removed 143-line legacy code path
- **`action_close.sh`** — rewritten from 92 → 47 lines using `lib/common.sh` close functions
- **Instance YAMLs** — `type:` → `layout:`, `runner: split` → `terminal: iterm` + `mode: tile`
- **Layout YAMLs** — added `terminal:` field, removed `runner:` field
- **Status output** — shows `terminal/mode` instead of runner name, `Layouts:` instead of `Types:`
- **`yb init`** — uses `layouts/` directory, creates `layout:` field in new instances
- **Backward compatibility** — old `type:` and `runner:` fields still work via mapping in yb.sh

### Removed
- **`runners/split.sh`** — app opening moved to yb.sh, layout is tile.sh
- **`runners/iterm.v003.sh`** — app opening moved to yb.sh, layout is tile.sh
- **`runners/iterm.sh`** — diagnostic script, never called
- **`sketchybar/plugins/space_label.sh`** — legacy yabai label dependency, unused

## v0.3.0 — Yabai integration & service management

### New
- **Yabai window tracking** — `iterm.v003` and `tile` runners use `yabai -m query --windows` for stable window IDs (title-independent)
- **Yabai positioning** — windows positioned via `--toggle float` + `--move abs:x:y` + `--resize abs:w:h` instead of JXA System Events
- **Service auto-start** — `yb.sh` ensures yabai and sketchybar are running before any workspace launch; starts them automatically if down
- **Space diagnostics** — `iterm.v003` reports which macOS space each window landed on after creation
- **iTerm2 session-path lookup** — `tile.sh` finds iTerm2 windows by `variable named "session.path"` when title doesn't contain folder name (e.g. Claude Code changes title to "✳ Claude Code")
- **Self-sustained types** — types carry runner, cmd, bar, zoom, and layout; thin instances reference a type and only add path + display
- **`yb init`** — creates a thin instance for CWD from any type (`yb init claudedev 3`)
- **Close button** — SketchyBar X icon destroys workspace (closes VS Code by title, iTerm2 by session path, Terminal by title)
- **Display migration** — `yb <instance> <new_display>` detects display change, closes old workspace, rebuilds on new display
- **Instances: `claude`, `puff`** — claudedev type, iTerm2 runner, Claude Code in terminal

### Changed
- `runners/iterm.v003.sh` — rewritten: yabai-first with JXA fallback, snapshot delta for window detection, `open -n` for current-space placement
- `runners/tile.sh` — rewritten: yabai-first path with session-path iTerm2 lookup, JXA fallback preserved
- `yb.sh` — added `ensure_services()` before destroy/init/launch paths
- README updated with yabai integration, service management, updated runner docs

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
