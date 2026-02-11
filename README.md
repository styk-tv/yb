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

```
yb mm 3
```

1. Checks if workspace `mm` is already open &mdash; if so, switches to it
2. Finds or creates an empty virtual desktop on display 3
3. Opens VS Code + Terminal for `~/git_ckp/mermaid`, tiles them side-by-side
4. Configures SketchyBar with label **MM**
5. Applies zoom level if configured

```
=== yb: mm → split on display 3 ===

[space] Found empty desktop on display 3 (delta=-2) — reusing
[open]  Visual Studio Code → /Users/you/git_ckp/mermaid
[open]  Terminal → cd /Users/you/git_ckp/mermaid && clear
[tile]  Code [mermaid] 726,-1440 1720x1440
        Terminal [mermaid — -bash] 2446,-1440 1720x1440
[bar]   style=standard display=3 label=MM

=== Ready: MM ===
```

---

## Setup

```bash
git clone <repo> ~/.config/styk-tv/yb
cd ~/.config/styk-tv/yb
./setup.sh
```

`setup.sh` installs dependencies via Homebrew and symlinks configs:

| Dependency | Purpose |
|---|---|
| `yq` | YAML parser for instance/type configs |
| `jq` | JSON parser for display/space queries |
| `yabai` | Window manager (optional, for BSP mode) |
| `sketchybar` | Status bar with workspace labels |

Add to your shell profile:

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

If the workspace is already open, `yb` detects it via `code --status` and switches to the existing window and space instead of creating a new one.

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
padding: 0,0,0,0
zoom: 0
cmd: null
```

| Field | Type | Default | Description |
|---|---|---|---|
| `runner` | string | &mdash; | Runner script: `split`, `solo` |
| `path` | string | &mdash; | Workspace folder (supports `~`) |
| `display` | int | `4` | Target display ID |
| `bar` | string | `none` | SketchyBar style: `standard`, `minimal`, `none` |
| `gap` | int | `0` | Pixel gap between tiled windows |
| `padding` | string | `0,0,0,0` | Display edge padding: `top,bottom,left,right` |
| `zoom` | int | `0` | VS Code zoom level (Cmd+= presses) |
| `cmd` | string | `null` | Terminal command (runs after `cd` to workspace) |

### Included instances

| Name | Path | Runner | Bar | Notes |
|---|---|---|---|---|
| `mm` | `~/git_ckp/mermaid` | split | standard | Mermaid project |
| `dev` | `~/.config/styk-tv/yb` | split | standard | YB self-hosting, gap=12 |
| `ai` | `~/code/ai-experiments` | split | minimal | Runs `claude dev`, zoom +1 |
| `styk` | `~/code/styk-tv` | split | none | Runs `npm run dev`, zoom +2 |

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
- Opens new Terminal tab with `do script`
- Polls up to 15s for Code window matching the workspace folder name
- Tiles Code (left half) + Terminal (right half) using JXA coordinate positioning
- Window matching uses exact VS Code title pattern: `title === folder` or `title.endsWith(" — " + folder)`

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

Configures SketchyBar on a display.

```bash
./runners/bar.sh --style standard --display 3 --label "MERMAID"
```

Delegates to style scripts in `sketchybar/bars/`.

---

## Types (legacy)

YAML files in `types/` define layout templates used by the legacy `type:` field in instances.

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
  border: on
```

| Mode | Description |
|---|---|
| `tile` | JXA coordinate positioning on target display (no yabai needed) |
| `splitview` | macOS native Split View via AppleScript + CG mouse events |
| `bsp` | Yabai BSP tiling with labeled spaces (requires yabai running) |

---

## SketchyBar

Three bar styles available:

| Style | Height | Blur | Look |
|---|---|---|---|
| `standard` | 32px | 20 | Semi-transparent with blur, rounded corners |
| `minimal` | 24px | 0 | Thin, flat, label only |
| `none` | &mdash; | &mdash; | Hidden |

Bar configs live in `sketchybar/bars/`. The global config at `sketchybar/sketchybarrc` is symlinked by `setup.sh`.

Each workspace gets a label (instance name uppercased) shown in the bar &mdash; this serves as the space naming mechanism since macOS doesn't expose space renaming APIs.

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

---

## Project structure

```
yb/
├── yb.sh                     # CLI entrypoint
├── setup.sh                  # Install deps, symlink configs
├── .gitignore
├── instances/                # Workspace definitions
│   ├── ai.yaml
│   ├── dev.yaml
│   ├── mm.yaml
│   └── styk.yaml
├── types/                    # Layout templates (legacy)
│   ├── claudedev.yaml
│   ├── omegadev.yaml
│   ├── splitdev.yaml
│   └── standard.yaml
├── runners/                  # Action scripts
│   ├── split.sh              # VS Code + Terminal tiled
│   ├── solo.sh               # Single app fullscreen
│   ├── space.sh              # Virtual desktop management
│   ├── bar.sh                # SketchyBar configuration
│   └── iterm.sh              # iTerm2 diagnostic (broken)
├── sketchybar/
│   ├── sketchybarrc          # Global bar config
│   ├── bars/
│   │   ├── standard.sh       # Blurred, rounded
│   │   ├── minimal.sh        # Thin, flat
│   │   └── none.sh           # Hidden
│   └── plugins/
│       └── space_label.sh    # Dynamic label from yabai
└── yabai/
    └── config.yabairc        # Window manager defaults
```

---

## Known issues

- **iTerm2** &mdash; Programmatic window creation is broken on this system (all 8 methods tested in `runners/iterm.sh` fail). Terminal.app is used as the fallback.
- **Space renaming** &mdash; macOS stores space names in WindowServer internals, not in any writable plist. SketchyBar labels are used instead.
- **Mission Control** &mdash; Space creation opens Mission Control which steals focus. Cannot be run from within a tool that requires foreground access (e.g., Claude Code tool calls).
