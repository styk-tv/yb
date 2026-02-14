# YB

**Workspace orchestrator for macOS multi-display setups.**

![macOS](https://img.shields.io/badge/macOS-Sonoma%2B-000?logo=apple&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![SIP](https://img.shields.io/badge/SIP-enabled-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)
![yabai](https://img.shields.io/badge/yabai-integrated-yellow)
![sketchybar](https://img.shields.io/badge/sketchybar-integrated-orange)

One command spawns a full development workspace &mdash; VS Code + iTerm2 tiled on a target display, on its own virtual desktop, with a labeled status bar. YAML-driven config, no SIP modification required.

---

## How it works

A workspace is assembled from small, independent pieces. You pick a **terminal** (which app to open), a **mode** (how windows are laid out), a **bar style** (what the status bar looks like), **padding/gap** (how windows are spaced), and a **target display**. YB composes them into a single command.

### 1. Define a layout or instance

A **layout** is a reusable workspace template &mdash; terminal choice, tiling mode, bar style, gaps, and padding:

```yaml
# layouts/standard.yaml
terminal: iterm
mode: tile
bar: standard
layout:
  gap: 12
  padding_top: 12
  padding_bottom: 12
  padding_left: 12
  padding_right: 12
```

An **instance** is a named workspace. It can be a **thin reference** to a layout (inheriting terminal, mode, bar, cmd, zoom, and padding), or a **standalone** definition with all fields inline:

```yaml
# instances/puff.yaml — thin (layout provides everything)
layout: claudedev
path: ~/git_ckp/puff
display: 3
```

```yaml
# instances/mm.yaml — standalone (all fields inline)
terminal: iterm
mode: tile
path: ~/git_ckp/mermaid
display: 4
bar: standard
gap: 0
padding: 52,0,0,0
zoom: 0
cmd: null
```

Create a thin instance from any directory with `yb init`:

```bash
cd ~/my-project
yb init claudedev 3    # creates instances/my-project.yaml
yb my-project          # launch it
```

You can also launch a layout ad-hoc (`yb standard 3` uses your CWD), or launch a named instance (`yb mm 3`) for a fully configured workspace.

### 2. Launch

```
yb mm 3
```

YB reads the instance, then runs each piece in sequence:

1. Checks if workspace `mm` is already open &mdash; if so, switches to it (re-tiles windows, updates bar)
2. `runners/space.sh` &mdash; finds or creates an empty virtual desktop on display 3
3. Opens VS Code + iTerm2 (based on `terminal:` field)
4. `runners/tile.sh` &mdash; positions windows side-by-side using yabai (JXA fallback)
5. Writes command to iTerm2 session
6. `runners/bar.sh` &mdash; configures SketchyBar with label **MM**, workspace path, and action icons
7. Applies zoom level if configured

```
=== yb: mm → iterm/tile on display 3 ===

[space] Found empty desktop on display 3 (delta=-2) — reusing
[12:34:56.78] opening VS Code → /Users/you/git_ckp/mermaid
[12:34:56.90] opening iTerm2
[12:34:59.12] Code window 'mermaid' found (poll 1)
[12:34:59.20] tile: left=726,-1440 1720x1440  right=2446,-1440 1720x1440
[12:34:59.30] tile: Code wid=37021 → 726,-1440 1720x1440
[12:34:59.40] tile: terminal wid=37023 → 2446,-1440 1720x1440
[bar]   style=standard display=3->sbar=2 label=MM path=~/git_ckp/mermaid

=== Ready: MM ===
```

Each runner is a standalone script &mdash; `bar.sh` knows nothing about `tile.sh`, and `space.sh` knows nothing about either. YB is the orchestrator that wires them together based on your YAML.

---

## Requirements

### Homebrew packages

Installed automatically by `setup.sh`:

```bash
brew install yq jq
brew install koekeishiya/formulae/yabai
brew install koekeishiya/formulae/skhd
brew tap felixkratz/formulae
brew install sketchybar
```

| Package | Tap | Purpose |
|---|---|---|
| `yq` | &mdash; | YAML parser for instance/layout configs |
| `jq` | &mdash; | JSON parser for display/space queries |
| `yabai` | `koekeishiya/formulae` | Window manager &mdash; window tracking + positioning (SIP-enabled), BSP tiling (SIP-disabled) |
| `skhd` | `koekeishiya/formulae` | Hotkey daemon (optional, for keybindings) |
| `sketchybar` | `felixkratz/formulae` | Status bar with workspace labels and icons |

### Font

**Hack Nerd Font** is required for SketchyBar icon rendering:

```bash
brew install --cask font-hack-nerd-font
```

### System requirements

| Requirement | Notes |
|---|---|
| macOS Sonoma+ | Uses Mission Control automation, System Events, JXA |
| python3 | Ships with macOS; used for plist parsing, display coordinate matching, Unicode icon generation |
| Visual Studio Code | Must be launchable via `open -a "Visual Studio Code"` and have `code` CLI in PATH |
| iTerm2 | Default terminal &mdash; launched via `open -n -a "iTerm"`, command written via AppleScript session |
| Accessibility permissions | System Events, CGEvent APIs, and yabai all require accessibility access in System Settings &rarr; Privacy &rarr; Accessibility |

---

## Setup

```bash
git clone <repo> ~/.config/styk-tv/yb
cd ~/.config/styk-tv/yb
./setup.sh
```

`setup.sh` installs all Homebrew packages, then symlinks configs:

| Source | Target |
|---|---|
| `yabai/config.yabairc` | `~/.yabairc` |
| `sketchybar/sketchybarrc` | `~/.config/sketchybar/sketchybarrc` |

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
alias yb='~/.config/styk-tv/yb/yb.sh'
```

---

## Usage

### Status

```bash
yb
```

Shows services, instances, layouts, runners, and connected displays:

```
yb - workspace orchestrator

  yabai on        sketchybar on       sip enabled

Instances:
  ai       iterm/tile               display=4    bar=minimal     ~/code/ai-experiments
  claude   iterm/tile (claudedev)   display=4    bar=standard    ~/git_ckp/mermaid
  dev      iterm/tile               display=4    bar=standard    ~/.config/styk-tv/yb
  mm       iterm/tile               display=4    bar=standard    ~/git_ckp/mermaid
  puff     iterm/tile (claudedev)   display=3    bar=standard    ~/git_ckp/puff
  styk     iterm/tile               display=4    bar=none        ~/code/styk-tv

Layouts:
  claudedev    terminal=iterm      mode=tile       bar=standard    cmd=unset CLAUDECODE && claude
  omegadev     terminal=iterm      mode=tile       bar=none        cmd=—
  splitdev     terminal=iterm      mode=splitview  bar=standard    cmd=—
  standard     terminal=iterm      mode=tile       bar=standard    cmd=—

Runners:
  bar          Configure sketchybar for a workspace
  solo         Layout-only: positions a single app window fullscreen
  space        Create/list virtual desktops (Spaces) via Mission Control
  tile         Layout-only: finds existing VS Code + terminal windows and tiles them

Displays:
  4    LC49G95T             5120x1440 *
  1    Color LCD            3024x1964
  3    S34J55x              3440x1440
```

### Launch workspace

```bash
yb <instance> [display_id]
```

```bash
yb mm          # launch mermaid on default display (4)
yb mm 3        # launch mermaid on display 3
yb ai          # launch ai-experiments with "claude dev" in terminal
yb styk        # launch styk-tv with "npm run dev", zoom +2
```

If the workspace is already open, `yb` detects it via `code --status` and switches to the existing window and space instead of creating a new one. On switch, windows are re-tiled and the bar is refreshed. If a different display is specified, the workspace is migrated &mdash; windows and bar on the old display are closed, then rebuilt fresh on the new one.

### Ad-hoc workspace from layout

```bash
yb <layout> [display_id]
```

```bash
yb standard 3  # tile CWD with gap=12, standard bar on display 3
yb omegadev    # tile CWD with no bar, no gaps
```

Uses the current working directory as workspace path. Terminal, mode, and bar style come from the layout definition.

### List spaces

```bash
./runners/space.sh --list
```

### Destroy workspace (yabai BSP mode)

```bash
yb -d <space_label>
```

---

## Instances

YAML files in `instances/` define named workspaces. Instances can be **thin** (reference a layout) or **standalone** (all fields inline).

**Thin instance** (layout-based):
```yaml
# instances/puff.yaml
layout: claudedev
path: ~/git_ckp/puff
display: 3
```

**Standalone instance**:
```yaml
# instances/mm.yaml
terminal: iterm
mode: tile
path: ~/git_ckp/mermaid
display: 4
bar: standard
gap: 0
padding: 52,0,0,0
zoom: 0
cmd: null
```

| Field | Type | Default | Description |
|---|---|---|---|
| `layout` | string | &mdash; | Reference to a layout YAML (inherits terminal, mode, bar, cmd, zoom, padding) |
| `terminal` | string | `iterm` | Terminal app: `iterm`, `terminal`, `none` |
| `mode` | string | `tile` | Layout mode: `tile`, `solo`, `splitview` |
| `path` | string | &mdash; | Workspace folder (supports `~`) |
| `display` | int | `4` | Target display CGDirectDisplayID |
| `bar` | string | `none` | SketchyBar style (overrides layout) |
| `gap` | int | `0` | Pixel gap between tiled windows (overrides layout) |
| `padding` | string | `0,0,0,0` | Display edge padding: `top,bottom,left,right` (overrides layout) |
| `zoom` | int | `0` | VS Code zoom level (overrides layout) |
| `cmd` | string | `null` | Terminal command (overrides layout) |

When using `layout:`, all fields except `path` and `display` are inherited from the layout. Any field set directly on the instance overrides the layout.

### Included instances

| Name | Layout | Path | Terminal | Mode | Bar | Notes |
|---|---|---|---|---|---|---|
| `mm` | &mdash; | `~/git_ckp/mermaid` | iterm | tile | standard | Mermaid project |
| `dev` | &mdash; | `~/.config/styk-tv/yb` | iterm | tile | standard | YB self-hosting |
| `ai` | &mdash; | `~/code/ai-experiments` | iterm | tile | minimal | Runs `claude dev` |
| `styk` | &mdash; | `~/code/styk-tv` | iterm | tile | none | Runs `npm run dev` |
| `claude` | claudedev | `~/git_ckp/mermaid` | iterm | tile | standard | Claude Code via iTerm2 |
| `puff` | claudedev | `~/git_ckp/puff` | iterm | tile | standard | Claude Code via iTerm2 |

---

## Layouts

YAML files in `layouts/` define reusable workspace templates. A layout carries terminal choice, mode, command, bar style, zoom, and padding. Thin instances reference a layout and only add `path:` and `display:`.

```yaml
# layouts/claudedev.yaml
terminal: iterm
cmd: unset CLAUDECODE && claude
mode: tile
bar: standard
zoom: 1
layout:
  gap: 0
  padding_top: 0
  padding_bottom: 0
  padding_left: 0
  padding_right: 0
```

| Field | Values | Description |
|---|---|---|
| `terminal` | `iterm`, `terminal`, `none` | Terminal app to open alongside VS Code |
| `cmd` | string | Terminal command (runs after `cd` to workspace) |
| `mode` | `tile`, `solo`, `splitview` | Layout mode (see below) |
| `bar` | `standard`, `minimal`, `none` | SketchyBar style |
| `zoom` | int | VS Code zoom level (Cmd+= presses) |
| `layout.gap` | int | Pixel gap between windows |
| `layout.padding_*` | int | Edge padding (top, bottom, left, right) |

When an instance uses `layout:`, bar height is auto-added to top padding (52px for standard, 34px for minimal).

### Layout modes

| Mode | Description |
|---|---|
| `tile` | Yabai float + move + resize (falls back to JXA coordinate positioning) |
| `splitview` | macOS native Split View via AppleScript + CG mouse events |
| `solo` | Single app fullscreen on target display |

### Included layouts

| Name | Terminal | Mode | Bar | Cmd | Description |
|---|---|---|---|---|---|
| `standard` | iterm | tile | standard | &mdash; | Relaxed look with gaps and borders |
| `claudedev` | iterm | tile | standard | `unset CLAUDECODE && claude` | Claude Code via iTerm2, zoom +1 |
| `omegadev` | iterm | tile | none | &mdash; | Zero UI, no bar, no gaps |
| `splitdev` | iterm | splitview | standard | &mdash; | macOS native split view |

---

## Shared library

`lib/common.sh` provides shared functions used by runners, `yb.sh`, and plugins. It handles yabai-vs-JXA decisions internally so callers don't contain fallback logic.

| Function | Purpose |
|---|---|
| `yb_ts` | Timestamp (HH:MM:SS.mmm) |
| `yb_log` | Timestamped log output |
| `yb_yabai_ok` | Check yabai availability (memoized) |
| `yb_display_frame $did` | Display geometry as X:Y:W:H (yabai or JXA) |
| `yb_tile_geometry $frame ...` | Compute left/right tile coordinates (exports YB_X0 etc.) |
| `yb_find_code $folder` | Find VS Code window by folder name |
| `yb_find_iterm $path` | Find iTerm2 window by session working directory |
| `yb_find_terminal $folder` | Find Terminal.app window by title |
| `yb_position $wid $x $y $w $h` | Position window (yabai float+move+resize or JXA) |
| `yb_close_code $folder` | Close VS Code window |
| `yb_close_iterm $path` | Close iTerm2 window by session path |
| `yb_close_terminal $folder` | Close Terminal.app window by title |

`lib/display_frame.jxa` is a standalone JXA script for display geometry when yabai is unavailable.

---

## Runners

Scripts in `runners/` handle specific workspace actions. Each runner is a standalone script invoked by `yb.sh`. Runners are **layout-only** &mdash; they find and position existing windows. App opening is handled by `yb.sh`.

### `tile`

Finds existing VS Code + terminal windows and tiles them side-by-side on a target display.

```bash
./runners/tile.sh --display 3 --path ~/project [--gap 12] [--pad 12,12,12,12]
```

- Uses `lib/common.sh` for window finding and positioning
- Finds Code by folder name, iTerm2 by session path, Terminal by title
- Yabai positioning with JXA fallback (handled transparently by library)

### `solo`

Positions a single VS Code window fullscreen on a target display.

```bash
./runners/solo.sh --display 3 --path ~/project [--pad 0,0,0,0]
```

### `space`

Creates or lists virtual desktops via Mission Control. Works with SIP enabled.

```bash
./runners/space.sh --list
./runners/space.sh --create --display 3
```

**Create** checks for empty desktops first:
1. Maps display ID &rarr; UUID via `CGDisplayCreateUUIDFromDisplayID`
2. Reads `com.apple.spaces` plist to find the monitor
3. A desktop is "empty" if all its window IDs also appear on other desktops
4. If empty desktop found &rarr; navigates directly (ctrl+arrow)
5. If none &rarr; opens Mission Control, hovers to reveal "+", clicks to create, navigates to new space

### `bar`

Configures SketchyBar for a workspace on a specific display.

```bash
./runners/bar.sh --style standard --display 3 --label "MM" --path ~/git_ckp/mermaid
```

- **Probe-based display targeting** &mdash; resolves SketchyBar display index via bounding_rects + CG coordinate matching
- **Space binding** &mdash; resolves display UUID, reads `com.apple.spaces` plist, sets `associated_space` on all items
- Delegates to style scripts in `sketchybar/bars/`

---

## SketchyBar

Three bar styles, configured per-instance or per-layout via the `bar:` YAML field.

### Styles

| Style | Height | Look |
|---|---|---|
| `standard` | 32px | Semi-transparent blur, rounded corners, [YB] badge + name + path + action icons |
| `minimal` | 24px | Flat, workspace name + path only |
| `none` | &mdash; | Bar hidden |

### Standard bar layout

```
┌─────────────────────────────────────────────────────────────┐
│ [YB]  WORKSPACE  ~/path/to/project          ≡  >_  📁  ✕  │
│ badge  label      path (dimmed)         code term dir close │
└─────────────────────────────────────────────────────────────┘
```

- **Left**: [YB] badge (white pill), workspace name (bold), workspace path (dimmed)
- **Right**: Action icons using Hack Nerd Font glyphs
- **Close button**: Clicking X closes VS Code (by title match), iTerm2 (by session path), Terminal (by title), removes bar items, hides bar. Uses `lib/common.sh` close functions.

### Display targeting

SketchyBar's display index doesn't match NSScreen order or CGDirectDisplayID. The `bar.sh` runner uses a probe-based approach to resolve the correct display.

### Space-aware items

Bar items are bound to a specific Mission Control space via `associated_space` so they only appear on the YB-managed desktop.

### Config files

| File | Purpose |
|---|---|
| `sketchybar/sketchybarrc` | Global config (symlinked to `~/.config/sketchybar/`). Intentionally empty |
| `sketchybar/bars/standard.sh` | Standard style: badge + labels + action icons |
| `sketchybar/bars/minimal.sh` | Minimal style: name + path |
| `sketchybar/bars/none.sh` | Hides bar |
| `sketchybar/plugins/icon_hover.sh` | Hover highlight effect for action icons |
| `sketchybar/plugins/action_close.sh` | Close workspace on X click (uses lib/common.sh) |

---

## Display detection

YB identifies displays by their `CGDirectDisplayID` (integer), obtained from `NSScreen.deviceDescription["NSScreenNumber"]`. These IDs are stable across reboots and shown in `yb` status output.

When yabai is running, display frames come from `yabai -m query --displays` (matched by CGDirectDisplayID via `.id`). Windows are positioned via `yabai -m window --toggle float` + `--move abs:x:y` + `--resize abs:w:h`. Fallback uses JXA with `ObjC.import("AppKit")` for display geometry and System Events for window positioning.

---

## Workspace switching

When `yb <instance>` is called for an already-open workspace:

1. **Detection** &mdash; `code --status` checks for exact `Folder (<name>):` match
2. **Window lookup** &mdash; JXA finds the Code window by precise title match
3. **Display check** &mdash; determines which display the window is on

**Same display** (refresh):
- `open -a "Visual Studio Code"` brings the window to front
- `runners/tile.sh` repositions windows via library
- `runners/bar.sh` recreates any missing items

**Different display** (migration):
- Closes VS Code, iTerm2, Terminal via `lib/common.sh` close functions
- Removes bar items
- Falls through to fresh creation on the new display

---

## Yabai integration

YB uses yabai in two ways:

1. **Window tracking** (SIP enabled) &mdash; `yabai -m query --windows` provides stable window IDs, space indices, and display indices
2. **Window positioning** (SIP enabled) &mdash; `yabai -m window --toggle float` + `--move abs:x:y` + `--resize abs:w:h`

All yabai interactions go through `lib/common.sh` which falls back to JXA when yabai is unavailable.

**Service management** &mdash; `yb.sh` ensures yabai and sketchybar are running before any workspace launch. If a service is down, it starts it automatically.

### Config

Global defaults in `yabai/config.yabairc` (symlinked to `~/.yabairc`):

```
layout          bsp
window_placement second_child
mouse_modifier  alt
mouse_action1   move
mouse_action2   resize
window_gap      10
padding         10 (all sides)
```

These apply to desktops not managed by YB. YB workspaces override gap and padding per-instance or per-layout.

---

## Project structure

```
yb/
├── yb.sh                         # CLI entrypoint + orchestrator
├── setup.sh                      # Install deps, symlink configs
├── CHANGELOG.md
├── PLAN.v0.4.0.md
├── .gitignore
├── lib/                          # Shared library
│   ├── common.sh                 # Window finding, positioning, display, close
│   └── display_frame.jxa         # JXA display geometry fallback
├── instances/                    # Workspace definitions
│   ├── ai.yaml
│   ├── claude.yaml
│   ├── dev.yaml
│   ├── mm.yaml
│   ├── puff.yaml
│   └── styk.yaml
├── layouts/                      # Reusable workspace templates
│   ├── claudedev.yaml
│   ├── omegadev.yaml
│   ├── splitdev.yaml
│   └── standard.yaml
├── runners/                      # Layout + action scripts
│   ├── tile.sh                   # Tile Code + terminal side-by-side
│   ├── solo.sh                   # Single app fullscreen
│   ├── space.sh                  # Virtual desktop management
│   └── bar.sh                    # SketchyBar orchestrator
├── sketchybar/
│   ├── sketchybarrc              # Global config (empty, all via bar.sh)
│   ├── bars/
│   │   ├── standard.sh           # Blur, rounded, badge + icons
│   │   ├── minimal.sh            # Thin, flat, name + path
│   │   └── none.sh               # Hidden
│   └── plugins/
│       ├── icon_hover.sh         # Mouse hover highlight effect
│       └── action_close.sh       # Close workspace on X click
└── yabai/
    └── config.yabairc            # Window manager defaults
```

---

## Architecture

```
Instance YAML          Layout YAML           Library
┌──────────┐          ┌──────────┐         ┌──────────────┐
│ path     │─layout──▶│ terminal │         │ lib/common.sh│
│ display  │          │ mode     │         │              │
│ (overrides)│        │ cmd      │         │ yb_find_*()  │
└──────────┘          │ bar      │         │ yb_position()│
                      │ zoom     │         │ yb_close_*() │
                      │ layout:  │         │ yb_display_* │
                      └──────────┘         └──────┬───────┘
                                                  │
yb.sh (orchestrator)                              │
┌─────────────────────────────────────────────────┤
│ 1. Resolve instance + layout                    │
│ 2. space.sh → create virtual desktop            │
│ 3. Open apps (VS Code + terminal)               │
│ 4. Wait for windows                             │
│ 5. runners/tile.sh or solo.sh ◀─────── uses ───┘
│ 6. Write cmd to terminal
│ 7. runners/bar.sh → SketchyBar
│ 8. Zoom
└─────────────────────────────────────────────────┘
```

---

## Known issues

- **macOS Spaces** &mdash; Windows opened with `open -n` may land on different spaces. YB works around this with space creation + navigation but can't guarantee same-space placement with SIP enabled.
- **Space renaming** &mdash; macOS stores space names in WindowServer internals, not in any writable plist. SketchyBar labels are used instead.
- **Mission Control** &mdash; Space creation opens Mission Control which steals focus. Cannot be run from within a tool that requires foreground access.
- **Bash 3.2** &mdash; macOS ships bash 3.2 which doesn't support `\u` Unicode escapes. Nerd Font icons are generated via `python3 -c "print('\ue7a8',end='')"`.
