# YB

**Workspace orchestrator for macOS multi-display setups.**

![macOS](https://img.shields.io/badge/macOS-Sonoma%2B-000?logo=apple&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![SIP](https://img.shields.io/badge/SIP-enabled-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)
![yabai](https://img.shields.io/badge/yabai-integrated-yellow)
![sketchybar](https://img.shields.io/badge/sketchybar-integrated-orange)

One command spawns a full development workspace &mdash; VS Code + iTerm2 tiled via yabai BSP on a target display, on its own virtual desktop, with a labeled status bar. YAML-driven config, multiple concurrent workspaces, no SIP modification required.

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
padding: 0,0,0,0
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

1. Checks if workspace `mm` is already open &mdash; if so, switches to it (refreshes bar, ensures secondary app)
2. `runners/space.sh` &mdash; finds or creates an empty virtual desktop on display 3
3. Configures yabai BSP on the new space (padding, gap, bar height)
4. `runners/bar.sh` &mdash; configures SketchyBar with namespaced items (e.g., **MM_badge**, **MM_label**)
5. Opens VS Code + iTerm2 via app handlers (`lib/app/*.sh`) &mdash; yabai auto-tiles them
6. Moves windows to correct space if they landed elsewhere
7. Enforces window order (primary left, secondary right) &mdash; swaps if needed
8. Applies zoom level if configured

```
=== yb: mm → code+iterm/tile on display 3 ===
[12:34:56.78] config: bar=standard bar_h=52 gap=0 pad=0,0,0,0
[12:34:56.80] step1: creating desktop on display=3
[12:34:57.00] step1: space=8 is empty — using it
[12:34:57.10] step1b: bar style=standard display=3 space=8
[bar][12:34:57.20] prefix=MM
[bar][12:34:57.50] items bound + updated
[12:34:57.60] step2: opening code + iterm
[12:35:00.80] step3: primary wid=37021 found (poll 1)
[12:35:00.90] step4: secondary wid=37023 (space=8)
[12:35:01.00] step5: order correct (primary left, secondary right)

=== Ready: MM ===
```

App handlers (`lib/app/code.sh`, `lib/app/iterm.sh`, etc.) provide open/find/close/focus/locate per app. The orchestrator contains zero app-specific code.

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
padding: 0,0,0,0
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

When an instance uses `layout:`, bar height is auto-added to top padding (queried from the bar script via `--height`).

### Layout modes

| Mode | Description |
|---|---|
| `tile` | Yabai BSP &mdash; two windows auto-tiled side-by-side |
| `solo` | Yabai BSP &mdash; single app fills the space |
| `splitview` | macOS native Split View via AppleScript + CG mouse events |

### Included layouts

| Name | Terminal | Mode | Bar | Cmd | Description |
|---|---|---|---|---|---|
| `standard` | iterm | tile | standard | &mdash; | Relaxed look with gaps and borders |
| `claudedev` | iterm | tile | standard | `unset CLAUDECODE && claude` | Claude Code via iTerm2, zoom +1 |
| `omegadev` | iterm | tile | none | &mdash; | Zero UI, no bar, no gaps |
| `splitdev` | iterm | splitview | standard | &mdash; | macOS native split view |

---

## Shared library

`lib/common.sh` provides shared functions used by runners, `yb.sh`, and plugins. Handles yabai-vs-JXA decisions internally.

| Function | Purpose |
|---|---|
| `yb_ts` | Timestamp (HH:MM:SS.mmm) |
| `yb_log` | Timestamped log output |
| `yb_yabai_ok` | Check yabai availability (memoized) |
| `yb_bar_height $style` | Query bar script for its padding reservation |
| `yb_visible_space $did` | Get visible space index on a display (CGDirectDisplayID) |
| `yb_space_bsp $space $gap ...` | Configure yabai space for BSP (padding + gap + bar height) |
| `yb_window_space $wid` | Get space index for a window |
| `yb_snapshot_wids $app` | Snapshot window IDs for delta tracking |
| `yb_find_new_wid $app $snap` | Find new window since snapshot |
| `yb_display_frame $did` | Display geometry as X:Y:W:H (yabai or JXA) |
| `yb_position $wid $x $y $w $h` | Position window (yabai or JXA; used by splitview fallback) |

### App handlers (`lib/app/*.sh`)

Each app module provides a standard interface:

| Function | Purpose |
|---|---|
| `app_<name>_open $path [$cmd]` | Launch the app with workspace path |
| `app_<name>_find $path [$space]` | Find window ID (optionally filtered by space) |
| `app_<name>_close $path` | Close the app's workspace window |
| `app_<name>_is_open $path` | Check if workspace is open (exit 0/1) |
| `app_<name>_focus $path` | Focus/activate an existing window |
| `app_<name>_locate $path` | Find window and return which display it's on |

Available handlers: `code` (VS Code), `iterm` (iTerm2), `terminal` (Terminal.app).

`lib/display_frame.jxa` is a standalone JXA script for display geometry when yabai is unavailable.

---

## Runners

Scripts in `runners/` handle infrastructure actions invoked by `yb.sh`. Window layout is managed by yabai BSP; app opening is handled by app handlers in `lib/app/`.

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

Configures SketchyBar for a workspace on a specific display. Items are namespaced per workspace.

```bash
./runners/bar.sh --style standard --display 3 --label "MM" --path ~/git_ckp/mermaid --space 8
```

- **Display resolution** &mdash; CGDirectDisplayID converted to yabai display index for sketchybar
- **Namespace prefix** &mdash; label (e.g., MM) used as item prefix: `MM_badge`, `MM_label`, `MM_path`, `MM_close`, etc.
- **Space binding** &mdash; all namespaced items bound to specific space via `associated_space`
- Delegates to style scripts in `sketchybar/bars/`

### `tile` / `solo` (legacy)

Manual positioning runners from pre-BSP architecture. Kept for splitview fallback but no longer called in the `tile` or `solo` BSP path.

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

### Namespaced items

Each workspace's bar items are prefixed with its label (e.g., `PUFF_badge`, `ONTOSYS_label`). This allows multiple workspaces to have independent bar items, each bound to their own space via `associated_space`. The close button extracts the prefix from `$NAME` to find the correct path item and remove only that workspace's items.

### Display targeting

CGDirectDisplayID is converted to yabai display index via `yabai -m query --displays` for sketchybar display pinning.

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
2. **Window lookup** &mdash; JXA locate finds the window and its display; if hidden space, focuses app first and retries
3. **Display check** &mdash; determines which display the window is on
4. **Shared-space check** &mdash; counts non-sticky windows on the space; if more than expected (another workspace's windows), closes stale and rebuilds

**Same display** (refresh):
- Re-applies BSP config and bar
- Focuses primary app
- Ensures secondary app is on the same space (finds, moves, or opens)

**Different display** (migration):
- Closes VS Code, iTerm2, Terminal via app handler close functions
- Removes namespaced bar items
- Falls through to fresh creation on the new display

---

## Yabai integration

YB uses yabai BSP tiling for workspace layout:

1. **BSP tiling** &mdash; `yabai -m config --space N layout bsp` with per-space padding and gap; windows auto-tile as they open
2. **Window tracking** &mdash; `yabai -m query --windows` provides stable window IDs, space indices, and display indices
3. **Window management** &mdash; `yabai -m window --space` moves windows between spaces, `--swap` enforces window order
4. **Space queries** &mdash; `yabai -m query --spaces` resolves visible space per display, validates window counts

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
├── .gitignore
├── lib/                          # Shared library + app handlers
│   ├── common.sh                 # BSP config, space queries, display, positioning
│   ├── display_frame.jxa         # JXA display geometry fallback
│   └── app/                      # Per-app open/find/close/focus/locate
│       ├── code.sh               # Visual Studio Code
│       ├── iterm.sh              # iTerm2
│       └── terminal.sh           # Terminal.app
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
├── runners/                      # Infrastructure scripts
│   ├── space.sh                  # Virtual desktop management
│   ├── bar.sh                    # SketchyBar orchestrator (namespaced)
│   ├── tile.sh                   # Legacy: manual tile positioning
│   └── solo.sh                   # Legacy: manual solo positioning
├── sketchybar/
│   ├── sketchybarrc              # Global config (empty, all via bar.sh)
│   ├── bars/
│   │   ├── standard.sh           # Dark bar, badge + icons (52px)
│   │   ├── minimal.sh            # Thin, flat, name + path (34px)
│   │   └── none.sh               # Hidden (0px)
│   └── plugins/
│       ├── icon_hover.sh         # Mouse hover highlight effect
│       └── action_close.sh       # Close workspace on X click (namespaced)
└── yabai/
    └── config.yabairc            # Window manager defaults
```

---

## Architecture

```
Instance YAML          Layout YAML           App Handlers
┌──────────┐          ┌──────────┐         ┌──────────────┐
│ path     │─layout──▶│ terminal │         │ lib/app/     │
│ display  │          │ mode     │         │  code.sh     │
│ (overrides)│        │ cmd      │         │  iterm.sh    │
└──────────┘          │ bar      │         │  terminal.sh │
                      │ zoom     │         └──────┬───────┘
                      │ layout:  │                │
                      └──────────┘         lib/common.sh
                                           ┌──────┴───────┐
                                           │ yb_space_bsp │
                                           │ yb_bar_height│
                                           │ yb_visible_* │
                                           └──────┬───────┘
yb.sh (orchestrator)                              │
┌─────────────────────────────────────────────────┤
│ 1.  Resolve instance + layout                   │
│ 1a. space.sh → create virtual desktop           │
│ 1b. yb_space_bsp → configure BSP     ◀── uses ─┘
│ 1c. bar.sh → namespaced SketchyBar items
│ 2.  Open apps via handlers (BSP auto-tiles)
│ 3.  Poll for primary window
│ 4.  Find/move secondary window
│ 5.  Enforce window order (swap if needed)
│ 6.  Post-setup (zoom)
└─────────────────────────────────────────────────┘
```

---

## Known issues

- **macOS Spaces** &mdash; Windows opened with `open -n` may land on different spaces. YB mitigates with Step 4b (window-to-space migration via `yabai -m window --space`).
- **SketchyBar single bar** &mdash; One sketchybar process = one bar configuration. Multiple workspaces share the global bar settings (height, position, color). Items are independent via namespacing.
- **JXA hidden spaces** &mdash; System Events can't see windows on non-visible macOS spaces. YB works around this by focusing the app first and retrying locate.
- **Space plist staleness** &mdash; `com.apple.spaces` plist can be stale after yabai window moves. YB validates via yabai window count after space.sh returns.
- **Space renaming** &mdash; macOS stores space names in WindowServer internals, not in any writable plist. SketchyBar labels are used instead.
- **Mission Control** &mdash; Space creation opens Mission Control which steals focus.
- **Bash 3.2** &mdash; macOS ships bash 3.2 which doesn't support `\u` Unicode escapes. Nerd Font icons are generated via `python3 -c "print('\ue7a8',end='')"`.
