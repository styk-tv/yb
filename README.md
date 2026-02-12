# YB

**Workspace orchestrator for macOS multi-display setups.**

![macOS](https://img.shields.io/badge/macOS-Sonoma%2B-000?logo=apple&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![SIP](https://img.shields.io/badge/SIP-enabled-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)
![yabai](https://img.shields.io/badge/yabai-optional-yellow)
![sketchybar](https://img.shields.io/badge/sketchybar-integrated-orange)

One command spawns a full development workspace &mdash; VS Code + Terminal tiled on a target display, on its own virtual desktop, with a labeled status bar. YAML-driven config, no SIP modification required.

---

## How it works

A workspace is assembled from small, independent pieces &mdash; each one a YAML field that maps to a runner script. You pick a **runner** (how apps launch), a **bar style** (what the status bar looks like), **padding/gap** (how windows are spaced), and a **target display**. YB composes them into a single command.

### 1. Define a type or instance

A **type** is a reusable layout template &mdash; tiling mode, bar style, gaps, and padding:

```yaml
# types/standard.yaml
mode: tile
bar: standard
layout:
  gap: 12
  padding_top: 12
  padding_bottom: 12
  padding_left: 12
  padding_right: 12
```

An **instance** is a named workspace that pins a type's look to a specific project folder, display, and terminal command:

```yaml
# instances/mm.yaml
runner: split          # launch VS Code + Terminal side-by-side
path: ~/git_ckp/mermaid
display: 4             # target display (CGDirectDisplayID)
bar: standard          # sketchybar style
gap: 0
padding: 52,0,0,0      # top,bottom,left,right
zoom: 0
cmd: null              # optional terminal command
```

You can launch a type ad-hoc (`yb standard 3` uses your CWD), or launch a named instance (`yb mm 3`) for a fully configured workspace.

### 2. Launch

```
yb mm 3
```

YB reads the instance, then runs each piece in sequence:

1. Checks if workspace `mm` is already open &mdash; if so, switches to it (re-tiles windows, updates bar)
2. `runners/space.sh` &mdash; finds or creates an empty virtual desktop on display 3
3. `runners/split.sh` &mdash; opens VS Code + Terminal for `~/git_ckp/mermaid`, tiles them side-by-side
4. `runners/bar.sh` &mdash; configures SketchyBar with label **MM**, workspace path, and action icons; binds items to the current Mission Control space
5. Applies zoom level if configured

```
=== yb: mm → split on display 3 ===

[space] Found empty desktop on display 3 (delta=-2) — reusing
[open]  Visual Studio Code → /Users/you/git_ckp/mermaid
[open]  Terminal → cd /Users/you/git_ckp/mermaid && clear
[tile]  Code [mermaid] 726,-1440 1720x1440
        Terminal [mermaid — -bash] 2446,-1440 1720x1440
[bar]   style=standard display=3->sbar=2 label=MM path=~/git_ckp/mermaid
[bar]   binding to space 7

=== Ready: MM ===
```

Each runner is a standalone script &mdash; `bar.sh` knows nothing about `split.sh`, and `space.sh` knows nothing about either. YB is the orchestrator that wires them together based on your YAML.

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
| `yq` | &mdash; | YAML parser for instance/type configs |
| `jq` | &mdash; | JSON parser for display/space queries |
| `yabai` | `koekeishiya/formulae` | Window manager (optional, for BSP mode) |
| `skhd` | `koekeishiya/formulae` | Hotkey daemon (optional, for keybindings) |
| `sketchybar` | `felixkratz/formulae` | Status bar with workspace labels and icons |

### Font

**Hack Nerd Font** is required for SketchyBar icon rendering:

```bash
brew install --cask font-hack-nerd-font
```

Used for workspace labels (Bold 11&ndash;13pt), path text (Regular 10&ndash;11pt), and action icons (Regular 14pt with Unicode glyphs from the Nerd Font private-use area).

### System requirements

| Requirement | Notes |
|---|---|
| macOS Sonoma+ | Uses Mission Control automation, System Events, JXA |
| python3 | Ships with macOS; used for plist parsing, display coordinate matching, Unicode icon generation |
| Visual Studio Code | Must be launchable via `open -a "Visual Studio Code"` and have `code` CLI in PATH |
| Terminal.app | macOS built-in; launched via AppleScript `do script` |
| Accessibility permissions | System Events and CGEvent APIs require accessibility access in System Settings &rarr; Privacy &rarr; Accessibility |

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

Shows services, instances, types, runners, and connected displays:

```
yb - workspace orchestrator

  yabai off       sketchybar on       sip enabled

Instances:
  ai       split    display=4    bar=minimal     ~/code/ai-experiments
  dev      split    display=4    bar=standard    ~/.config/styk-tv/yb
  mm       split    display=4    bar=standard    ~/git_ckp/mermaid
  styk     split    display=4    bar=none        ~/code/styk-tv

Types:
  claudedev    mode=tile        bar=minimal     gap=0
  omegadev     mode=tile        bar=none        gap=0
  splitdev     mode=splitview   bar=standard    gap=0
  standard     mode=tile        bar=standard    gap=12

Runners:
  bar          Configure sketchybar for a workspace
  iterm        iTerm2 automated launch tester
  solo         Opens a single app fullscreen on a target display
  space        Create/list virtual desktops (Spaces) via Mission Control
  split        Opens VS Code + Terminal side-by-side on a target display
  tile         Reposition existing Code + Terminal windows on a display

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

If the workspace is already open, `yb` detects it via `code --status` and switches to the existing window and space instead of creating a new one. On switch, windows are re-tiled and the bar is updated.

### Ad-hoc workspace from type

```bash
yb <type> [display_id]
```

```bash
yb standard 3  # tile CWD with gap=12, standard bar on display 3
yb omegadev    # tile CWD with no bar, no gaps
```

Uses the current working directory as workspace path. Layout and bar style come from the type definition.

### List spaces

```bash
./runners/space.sh --list
```

```
Monitor 1 (Main):  1 desktop(s), 2 fullscreen
    Desktop 1  (space 3) *
    [iTerm2]  (space 376)

Monitor 2 (CD5C490C...):  5 desktop(s), 0 fullscreen
    Desktop 1  (space 547)
    Desktop 2  (space 492)
    Desktop 3  (space 527)
    Desktop 4  (space 537)
    Desktop 5  (space 583) *
```

### Destroy workspace (yabai BSP mode)

```bash
yb -d <space_label>
```

---

## Instances

YAML files in `instances/` define named workspaces.

```yaml
# instances/mm.yaml
runner: split
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
| `runner` | string | &mdash; | Runner script: `split`, `solo` |
| `path` | string | &mdash; | Workspace folder (supports `~`) |
| `display` | int | `4` | Target display CGDirectDisplayID |
| `bar` | string | `none` | SketchyBar style: `standard`, `minimal`, `none` |
| `gap` | int | `0` | Pixel gap between tiled windows |
| `padding` | string | `0,0,0,0` | Display edge padding: `top,bottom,left,right` |
| `zoom` | int | `0` | VS Code zoom level (Cmd+= presses) |
| `cmd` | string | `null` | Terminal command (runs after `cd` to workspace) |

### Included instances

| Name | Path | Runner | Bar | Notes |
|---|---|---|---|---|
| `mm` | `~/git_ckp/mermaid` | split | standard | Mermaid project, padding 52,0,0,0 |
| `dev` | `~/.config/styk-tv/yb` | split | standard | YB self-hosting, gap=12, padding 52,12,12,12 |
| `ai` | `~/code/ai-experiments` | split | minimal | Runs `claude dev`, zoom +1, padding 34,0,0,0 |
| `styk` | `~/code/styk-tv` | split | none | Runs `npm run dev`, zoom +2 |

---

## Types

YAML files in `types/` define layout templates. Used directly via `yb <type>` or referenced by legacy instances.

```yaml
# types/standard.yaml
mode: tile
bar: standard
layout:
  engine: bsp
  gap: 12
  padding_top: 12
  padding_bottom: 12
  padding_left: 12
  padding_right: 12
  border: on
```

| Field | Values | Description |
|---|---|---|
| `mode` | `tile`, `splitview`, `bsp` | Tiling mode (see below) |
| `bar` | `standard`, `minimal`, `none` | SketchyBar style |
| `layout.gap` | int | Pixel gap between windows |
| `layout.padding_*` | int | Edge padding (top, bottom, left, right) |
| `layout.border` | `on`, `off` | Window borders (yabai BSP only) |

### Tiling modes

| Mode | Description |
|---|---|
| `tile` | JXA coordinate positioning on target display (no yabai needed) |
| `splitview` | macOS native Split View via AppleScript + CG mouse events |
| `bsp` | Yabai BSP tiling with labeled spaces (requires yabai running) |

### Included types

| Name | Mode | Bar | Gap | Description |
|---|---|---|---|---|
| `standard` | tile | standard | 12 | Relaxed look with gaps and borders |
| `claudedev` | tile | minimal | 0 | Clean look with thin bar |
| `omegadev` | tile | none | 0 | Zero UI, no bar, no gaps |
| `splitdev` | splitview | standard | 0 | macOS native split view |

---

## Runners

Scripts in `runners/` handle specific workspace actions. Each runner is a standalone script invoked by `yb.sh`.

### `split`

Opens VS Code + Terminal side-by-side on a target display.

```bash
./runners/split.sh --display 3 --path ~/project [--cmd "npm run dev"] [--gap 12] [--pad 12,12,12,12]
```

- Snapshots existing Terminal windows before launch
- Opens new VS Code instance with `open -na`
- Opens new Terminal tab with AppleScript `do script`
- Polls up to 15s for Code window matching the workspace folder name
- Tiles Code (left half) + Terminal (right half) using JXA coordinate positioning
- Window matching uses exact VS Code title pattern: `title === folder` or `title.endsWith(" — " + folder)`

### `tile`

Repositions existing Code + Terminal windows on a target display. Used when switching to an already-open workspace.

```bash
./runners/tile.sh --display 3 --path ~/project [--gap 12] [--pad 12,12,12,12]
```

### `solo`

Opens a single app fullscreen on a target display.

```bash
./runners/solo.sh --display 3 --path ~/project [--app "Visual Studio Code"] [--proc "Code"] [--pad 0,0,0,0]
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
3. A desktop is "empty" if all its window IDs also appear on other desktops (system windows like Dock/Finder exist everywhere)
4. If empty desktop found &rarr; navigates directly (ctrl+arrow)
5. If none &rarr; opens Mission Control, hovers to reveal "+", clicks to create, navigates to new space

### `bar`

Configures SketchyBar for a workspace on a specific display.

```bash
./runners/bar.sh --style standard --display 3 --label "MM" --path ~/git_ckp/mermaid
```

- **Probe-based display targeting** &mdash; SketchyBar uses its own display numbering that doesn't match NSScreen or CGDirectDisplayID. The runner sets `display=all`, adds a probe item, queries `bounding_rects` (which contain CG coordinates per display), and matches against NSScreen frames converted to CG coords using both X and Y axes
- **Space binding** &mdash; resolves the display UUID via `CGDisplayCreateUUIDFromDisplayID`, reads `com.apple.spaces` plist to find the current space's global index, then sets `associated_space` on all bar items so they only appear on the YB-managed desktop
- Delegates to style scripts in `sketchybar/bars/`

---

## SketchyBar

Three bar styles, configured per-instance or per-type via the `bar:` YAML field.

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
- **Right**: Action icons using Hack Nerd Font glyphs &mdash; VS Code (`\ue7a8`), Terminal (`\uf120`), Folder (`\uf07c`), Close (`\uf00d`)
- **Hover effect**: Icons get white background pill on `mouse.entered`, revert on `mouse.exited` (handled by `sketchybar/plugins/icon_hover.sh`)
- Icons generated via `python3 -c "print('\ue7a8',end='')"` because macOS bash 3.2 doesn't support `\u` Unicode escapes

### Display targeting

SketchyBar's display index doesn't match NSScreen order or CGDirectDisplayID. The `bar.sh` runner uses a probe-based approach:

1. Set bar to `display=all`
2. Add a temporary `_yb_probe` item
3. Query its `bounding_rects` &mdash; returns `display-N` keys with CG coordinate rectangles
4. Match each rectangle against NSScreen frames (converted to CG coordinates via `cgY = primaryH - nsY - height`)
5. Find which `display-N` contains the target CGDirectDisplayID's screen origin
6. Clean up probe, set bar to the discovered index

### Space-aware items

Bar items are bound to a specific Mission Control space via `associated_space` so they only appear on the YB-managed desktop, not all desktops on that display:

1. Get display UUID via JXA `CGDisplayCreateUUIDFromDisplayID` (requires `ObjC.castRefToObject` pattern)
2. Read `com.apple.spaces` plist via python3 `plistlib`
3. Count global space index across all monitors
4. Set `associated_space=<index>` on all bar items

### Config files

| File | Purpose |
|---|---|
| `sketchybar/sketchybarrc` | Global config (symlinked to `~/.config/sketchybar/`). Intentionally empty &mdash; all configuration applied by `bar.sh` |
| `sketchybar/bars/standard.sh` | Standard style: badge + labels + action icons |
| `sketchybar/bars/minimal.sh` | Minimal style: name + path |
| `sketchybar/bars/none.sh` | Hides bar |
| `sketchybar/plugins/icon_hover.sh` | Hover highlight effect for action icons |
| `sketchybar/plugins/space_label.sh` | Legacy label plugin (yabai-dependent, unused) |

---

## Display detection

YB identifies displays by their `CGDirectDisplayID` (integer), obtained from `NSScreen.deviceDescription["NSScreenNumber"]`. These IDs are stable across reboots and shown in `yb` status output.

Coordinate conversion between NSScreen (bottom-left origin) and System Events / CoreGraphics (top-left origin):

```
SE_y = primaryScreenHeight - NS_origin_y - NS_height
```

Window positions are set via System Events (`window.position`, `window.size`). Display frames come from `NSScreen.screens` via JXA with `ObjC.import("AppKit")`.

---

## Workspace switching

When `yb <instance>` is called for an already-open workspace:

1. **Detection** &mdash; `code --status` checks for exact `Folder (<name>):` match
2. **Window lookup** &mdash; JXA finds the Code window by precise title match (`=== folder` or `endsWith(" — " + folder)`)
3. **Display focus** &mdash; determines which display from window position, moves mouse to center, clicks
4. **Activation** &mdash; `open -a "Visual Studio Code"` brings the window to front; macOS auto-switches to its space
5. **Re-tile** &mdash; `runners/tile.sh` repositions Code + Terminal with correct padding
6. **Bar update** &mdash; `runners/bar.sh` refreshes the bar label and space binding

---

## Yabai config

Global defaults in `yabai/config.yabairc` (symlinked to `~/.yabairc`):

```
layout          bsp
window_placement second_child
mouse_modifier  alt
mouse_action1   move      (alt + left-drag)
mouse_action2   resize    (alt + right-drag)
window_gap      10
padding         10 (all sides)
window_shadow   on
window_border   on
```

These apply to desktops not managed by YB. YB workspaces override gap and padding per-instance or per-type.

---

## Project structure

```
yb/
├── yb.sh                         # CLI entrypoint
├── setup.sh                      # Install deps, symlink configs
├── CHANGELOG.md
├── .gitignore
├── instances/                    # Workspace definitions
│   ├── ai.yaml
│   ├── dev.yaml
│   ├── mm.yaml
│   └── styk.yaml
├── types/                        # Layout templates
│   ├── claudedev.yaml
│   ├── omegadev.yaml
│   ├── splitdev.yaml
│   └── standard.yaml
├── runners/                      # Action scripts
│   ├── split.sh                  # VS Code + Terminal tiled
│   ├── tile.sh                   # Reposition existing windows
│   ├── solo.sh                   # Single app fullscreen
│   ├── space.sh                  # Virtual desktop management
│   ├── bar.sh                    # SketchyBar orchestrator
│   └── iterm.sh                  # iTerm2 diagnostic (broken)
├── sketchybar/
│   ├── sketchybarrc              # Global config (empty, all via bar.sh)
│   ├── bars/
│   │   ├── standard.sh           # Blur, rounded, badge + icons
│   │   ├── minimal.sh            # Thin, flat, name + path
│   │   └── none.sh               # Hidden
│   └── plugins/
│       ├── icon_hover.sh         # Mouse hover highlight effect
│       └── space_label.sh        # Legacy label plugin (unused)
└── yabai/
    └── config.yabairc            # Window manager defaults
```

---

## Known issues

- **iTerm2** &mdash; Programmatic window creation is broken on this system (all 8 methods tested in `runners/iterm.sh` fail). Terminal.app is used as the fallback.
- **Space renaming** &mdash; macOS stores space names in WindowServer internals, not in any writable plist. SketchyBar labels are used instead.
- **Mission Control** &mdash; Space creation opens Mission Control which steals focus. Cannot be run from within a tool that requires foreground access (e.g., Claude Code tool calls).
- **Bash 3.2** &mdash; macOS ships bash 3.2 which doesn't support `\u` Unicode escapes. Nerd Font icons are generated via `python3 -c "print('\ue7a8',end='')"`.
