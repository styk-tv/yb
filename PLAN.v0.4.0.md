# v0.4.0 — Architecture: Separate Window from Layout + Shared Library

## Summary

Separate **which apps to open** (instance/layout concern) from **how to position them** (runner/layout concern). Extract shared code into `lib/common.sh`. Default to iTerm2 + yabai. JXA and sketchybar are optional fallbacks.

## Defaults

- **Terminal**: `iterm` (iTerm2 via `open -n`)
- **Positioning**: yabai (`float + move + resize`)
- **Bar**: optional — works without sketchybar running
- **Fallback**: JXA/System Events when yabai unavailable (degraded, not primary)

## Architecture

**Before** (runner = app + layout mixed):
```
runner: split       → opens Terminal.app + tiles via JXA
runner: iterm.v003  → opens iTerm2 + tiles via yabai+JXA
runner: solo        → opens app + fullscreens via JXA
```

**After** (terminal + mode separated):
```
terminal: iterm    + mode: tile   → yb.sh opens iTerm2, tile.sh positions via yabai
terminal: terminal + mode: tile   → yb.sh opens Terminal, tile.sh positions via yabai
terminal: none     + mode: solo   → yb.sh opens VS Code, solo.sh positions via yabai
```

## Folder rename: `types/` → `layouts/`

Reflects that these define workspace layout templates, not abstract types.

## New files

### `lib/common.sh`

Shared library sourced by all runners + yb.sh + plugins:

```
yb_ts()              timestamp HH:MM:SS.mmm
yb_log()             [component] message

yb_yabai_ok()        cached yabai availability check (0=yes, 1=no)

yb_display_frame()   CGDirectDisplayID → X:Y:W:H (yabai, fallback JXA)
yb_tile_geometry()   frame+pad+gap → exports YB_X0 YB_Y0 YB_HW YB_UH YB_X2 YB_W2

yb_find_code()       folder → window ID
yb_find_iterm()      work_path → window ID (session.path match)
yb_find_terminal()   folder → window ID (title match)

yb_position()        wid x y w h (yabai float+move+resize, fallback JXA)

yb_close_code()      folder → close Code window
yb_close_iterm()     work_path → close iTerm2 by session path
yb_close_terminal()  folder → close Terminal by title
```

### `lib/display_frame.jxa`

Standalone JXA for display geometry when yabai unavailable. Called by `yb_display_frame()`.

## Modified files

### Layout YAMLs (`layouts/*.yaml`, renamed from `types/`)

Add `terminal:` field to each:

| Layout | terminal | mode | bar | cmd |
|--------|----------|------|-----|-----|
| claudedev | iterm | tile | standard | `unset CLAUDECODE && claude` |
| standard | iterm | tile | standard | — |
| omegadev | iterm | tile | none | — |
| splitdev | iterm | splitview | standard | — |

Default terminal is `iterm` everywhere.

### Instance YAMLs (`instances/*.yaml`)

- `type:` → `layout:` (thin references)
- `runner:` → `terminal:` + `mode:` (standalone)

| Instance | layout | terminal | mode | path |
|----------|--------|----------|------|------|
| puff | claudedev | — | — | ~/git_ckp/puff |
| claude | claudedev | — | — | ~/git_ckp/mermaid |
| mm | — | terminal | tile | ~/git_ckp/mermaid |
| dev | — | iterm | tile | ~/.config/styk-tv/yb |
| ai | — | iterm | tile | ~/code/ai-experiments |
| styk | — | iterm | tile | ~/code/styk-tv |

### `runners/tile.sh` (~40 lines, was 315)

Layout-only. Sources `lib/common.sh`:

```bash
source "$REPO_ROOT/lib/common.sh"
FRAME=$(yb_display_frame "$DISPLAY_ID")
yb_tile_geometry "$FRAME" "$GAP" "$PAD_T" "$PAD_B" "$PAD_L" "$PAD_R"
CODE_WID=$(yb_find_code "$FOLDER_NAME")
TERM_WID=$(yb_find_iterm "$WORK_PATH")
[ -z "$TERM_WID" ] && TERM_WID=$(yb_find_terminal "$FOLDER_NAME")
[ -n "$CODE_WID" ] && yb_position "$CODE_WID" "$YB_X0" "$YB_Y0" "$YB_HW" "$YB_UH"
[ -n "$TERM_WID" ] && yb_position "$TERM_WID" "$YB_X2" "$YB_Y0" "$YB_W2" "$YB_UH"
```

### `runners/solo.sh` (~20 lines, was 93)

Layout-only for single-app fullscreen.

### `yb.sh`

1. `types/` refs → `layouts/`
2. `type:` field → `layout:`
3. `runner:` field → resolve `terminal:` + `mode:` (with backward compat mapping)
4. Inline app opening:
   ```bash
   open -na "Visual Studio Code" --args "$WORK_PATH"
   case "$TERMINAL" in
       iterm)    open -n -a "iTerm" ;;
       terminal) osascript ... do script ... ;;
       none)     ;;
   esac
   ```
5. Layout runner call: `"$REPO_ROOT/runners/$MODE.sh" --display ... --path ...`
6. iTerm command write (if terminal=iterm + cmd set)
7. Close logic → `yb_close_*()` from lib
8. `ensure_services()` makes sketchybar optional (only warn, don't fail)

### `sketchybar/plugins/action_close.sh`

Replace inline close with `source lib/common.sh` + `yb_close_*()`.

## Deleted files

| File | Reason |
|------|--------|
| `runners/split.sh` | App opening moves to yb.sh, layout is tile.sh |
| `runners/iterm.v003.sh` | App opening moves to yb.sh, layout is tile.sh |
| `runners/iterm.sh` | Dead diagnostic, never called |
| `sketchybar/plugins/space_label.sh` | Legacy, unused |

## Implementation order

1. `lib/common.sh` + `lib/display_frame.jxa`
2. `mv types/ layouts/` + add `terminal:` to all layout YAMLs
3. Update instance YAMLs (`type:` → `layout:`, `runner:` → `terminal:` + `mode:`)
4. Rewrite `runners/tile.sh` (layout-only, using lib)
5. Rewrite `runners/solo.sh` (layout-only, using lib)
6. Update `yb.sh` (layouts, inline app opening, layout runner dispatch, close via lib)
7. Update `action_close.sh` (close via lib)
8. Delete dead files
9. Update README + CHANGELOG

## Verification

1. `yb puff 3` — layout=claudedev, terminal=iterm: Code + iTerm2 tiled via yabai
2. `yb mm 3` — terminal=terminal: Code + Terminal.app tiled
3. `yb puff 3` (repeat) — switch: tile.sh re-positions
4. `yb` — status shows layouts + instances correctly
5. Close button works
6. Stop yabai → still works via JXA (degraded)
