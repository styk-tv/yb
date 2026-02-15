# Changelog

## v0.6.2 — Global layout isolation + multi-display bar + cold start fix

### Fixed
- **Non-YB spaces auto-tiling** — global yabai layout changed from `bsp` to `float`; YB-managed spaces get BSP explicitly via `yb_space_bsp()`, non-YB spaces remain float
- **Sketchybar covering non-YB windows** — changed `topmost=on` to `topmost=off`; on YB spaces, BSP padding pushes windows below the bar; on non-YB spaces, windows render over the empty bar
- **Bar invisible on cross-display workspaces** — changed `display=$DISPLAY` to `display=all` in bar styles; items self-select via `associated_space`, rendering on whichever display their space is visible on
- **`yb down` not killing skhd** — `skhd --stop-service` didn't terminate the process; added `pkill -x` fallback for all three services with post-shutdown verification
- **Cold start stuck in Mission Control** — `ensure_services()` used blind `sleep 2` after starting yabai; replaced with IPC readiness loop that polls `yabai -m query --spaces` up to 10 times before proceeding

### Changed
- **`yabai/config.yabairc`** — removed `window_destroyed` signal that reset all spaces to BSP; removed `external_bar` (doubles up with `yb_space_bsp` padding)
- **`sketchybar/bars/standard.sh`** — `topmost=off`, `display=all`
- **`sketchybar/bars/minimal.sh`** — `topmost=off`, `display=all`
- **`yb down`** — `pkill -x` fallback after each `--stop-service`; warns if any service survives shutdown
- **`ensure_services()`** — yabai IPC readiness polling (replaces `sleep 2`); skhd liveness check

## v0.6.1 — Fix subshell variable loss + bar sanity checks

### Fixed
- **State validate subshell bug** — `yb_state_validate` ran inside `$(...)` command substitution, causing `_SV_SPACE_IDX`, `_SV_PRIMARY_WID`, `_SV_SECONDARY_WID` to be lost when the subshell exited; intact path focused empty space instead of the correct one. Changed to direct invocation with `_SV_RESULT` variable
- **`no_state` return value** — `yb_state_validate` returned empty string instead of `"no_state"` when no manifest entry existed

### New
- **Bar Sanity section in analysis** — detects unbound items (visible on ALL spaces), duplicate space bindings (item overlaps), and label contamination (log text or unparsed JSON in `_path` labels)
- **SPACE_IDX numeric validation** in `bar.sh` — rejects non-numeric values (defense against stdout contamination from log functions)
- **DISPLAY_PATH contamination guard** in `bar.sh` — strips corrupted path labels containing log text

## v0.6.0 — State manifest: flawless idempotent workspace management

### New
- **State manifest** (`state/manifest.json`) — persistent workspace ownership tracking; stores window IDs, space UUIDs, display, mode, bar style, and work path per workspace
- **`lib/state.sh`** — new shared library with `yb_state_read`, `yb_state_get`, `yb_state_set`, `yb_state_remove`, `yb_state_clear`, `yb_state_validate`, `yb_state_build_json`
- **State-first validation** — `yb_state_validate` checks manifest against live yabai/sketchybar state before any discovery; returns one of: `intact`, `no_state`, `space_gone`, `primary_dead`, `secondary_dead`, `primary_drifted`, `secondary_drifted`, `order_wrong`, `bar_missing`, `bar_stale`
- **Zero-query fast path** — when state is `intact`, focuses space + primary app and exits immediately; no yabai window discovery, no title matching, no space search
- **Targeted repair** — each failure mode has a dedicated fix: swap windows (`order_wrong`), move window back (`*_drifted`), create bar (`bar_missing`), rebind bar (`bar_stale`); only the broken element is touched
- **Space UUID tracking** — manifest stores yabai space UUIDs that survive macOS space index renumbering; UUID resolved to current index on each run
- **Live Workspaces display** — `yb` (no args) shows a "Live Workspaces" section with space, display, window IDs, and liveness status from manifest
- **State Manifest section in analysis** — `runners/analysis.sh` shows owned WIDs per workspace with liveness check; `state-validate` added to checkpoint timeline

### Changed
- **`yb.sh`** — state validation inserted before section 2 (workspace check); state written at end of CREATE, REPAIR (switch), and FAST PATH (switch-intact)
- **`yb down`** — calls `yb_state_clear` to remove manifest when shutting down
- **`action_close.sh`** — calls `yb_state_remove` when closing a workspace via bar button
- **`lib/common.sh`** — sources `lib/state.sh`
- **`.gitignore`** — added `state/`
- **Backward compatible** — no state file means `no_state` → existing discovery logic runs unchanged; state is written after first successful CREATE or SWITCH

## v0.5.1 — Idempotent switch path

### Fixed
- **REBUILD fallthrough destroying workspaces** — second `yb` run closed all windows and fell through to CREATE, causing "desktops get created, everything starts moving". Removed REBUILD path entirely; replaced with REPAIR that fixes in-place and always exits
- **Log stdout contamination** — `yb_log` and `bar_log` output to stderr (`>&2`) to prevent command substitutions from capturing log text into variables

### Changed
- **Switch path collapsed** — FAST PATH (workspace intact → focus only) + REPAIR PATH (fix in-place → never fall through to CREATE); both always exit, never reach CREATE

## v0.5.0 — BSP tiling, app handlers, multi-workspace bars

### New
- **Yabai BSP tiling** — workspaces use `layout bsp` instead of float + manual positioning; yabai manages all window geometry automatically
- **App handler architecture** — `lib/app/*.sh` modules (code.sh, iterm.sh, terminal.sh) provide open/find/close/focus/locate per app; zero app-specific code in orchestrator
- **Bar height protocol** — bar scripts export their padding reservation via `--height` arg; `yb_bar_height()` queries it; eliminates hardcoded bar height values from yb.sh
- **Namespaced sketchybar items** — items prefixed with workspace label (e.g., `PUFF_badge`, `ONTOSYS_label`) so multiple workspaces coexist; each bound to its own space via `associated_space`
- **Multi-workspace support** — `yb ontosys 3 && yb puff 3` creates independent workspaces on the same display, each with its own bar items and space
- **Space validation** — after space.sh returns, yabai window count check prevents stale plist from causing space reuse; creates fresh space if target already has windows
- **Shared-space detection** — switch path counts non-sticky windows on space; if more than expected, closes stale windows and rebuilds
- **Window-to-space migration** — Step 4b moves windows to correct space via `yabai -m window --space` if they landed elsewhere
- **Window order enforcement** — checks primary/secondary `.frame.x` positions after BSP tiling; swaps with `yabai -m window --swap` if primary is on wrong side
- **Hidden-space recovery** — focus app first, retry locate (JXA can't see windows on non-visible spaces)
- **Switch path secondary app handling** — finds, moves, or opens secondary app when switching to existing workspace
- **`yb_visible_space()`** — resolves visible space index on a display (CGDirectDisplayID)
- **`yb_space_bsp()`** — configures yabai space for BSP with padding + gap + bar height
- **Usage hint** — `yb` status shows `yb init <layout> [display_id]` with example

### Changed
- **Bar launched before windows** — bar.sh runs at Step 1b (after space creation, before app opens) to establish namespace first
- **Bar display** — bar display configuration moved to style scripts; resolved via yabai display index
- **Standard bar** — background darkened (`0xff111111`), folder icon amber (`0xffe5c07b`)
- **Claudedev layout** — default gap changed from 0 to 10
- **Instance padding** — bar heights stripped from YAML padding values (now auto-added via `yb_bar_height()`): dev `52,12,12,12` → `12,12,12,12`, mm `52,0,0,0` → `0,0,0,0`, ai `34,0,0,0` → `0,0,0,0`
- **`runners/bar.sh`** — rewritten with timestamped logging, display index resolution, `--space` parameter, namespace prefix pass-through
- **`yb.sh`** — unified timestamped logging at every step; config dump, space validation, window moves with exit codes, swap decisions
- **`action_close.sh`** — extracts prefix from `$NAME` for namespaced item queries and removal

### Removed
- **Float positioning path** — no more `yabai -m space --layout float` + manual `yb_position()` calls
- **Manual layout dispatch** — `yb_layout_tile()` / `yb_layout_solo()` no longer called from BSP path (kept for splitview fallback)
- **Hardcoded bar heights** — removed `if standard→52 elif minimal→34` blocks from yb.sh

## v0.4.1 — Fix secondary window capture

- Grab focused wid after handler open for correct secondary window tracking

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
