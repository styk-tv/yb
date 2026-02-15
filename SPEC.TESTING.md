# YB Testing Specification

Pair-based test methodology for validating workspace orchestration. Workspaces collide at the second deployment &mdash; the first one always works. This spec defines the instrumentation, test sequences, and analysis pipeline that catch real failures.

---

## Mental model

```
Cycle 1 (deploy pair)        Cycle 2 (idempotent)        Cycle 3 (full reset)
┌────────────────────┐      ┌────────────────────┐      ┌────────────────────┐
│  yb down           │      │  yb ontosys 3      │      │  yb down           │
│  yb ontosys 3      │      │  → intact fast path │      │  yb ontosys 3      │
│  yb puff 3         │      │  yb puff 3          │      │  yb puff 3         │
│  → both CREATE     │      │  → intact fast path │      │  → both CREATE     │
└────────────────────┘      └────────────────────┘      └────────────────────┘
         ↓                           ↓                           ↓
   ┌──────────┐              ┌──────────┐              ┌──────────┐
   │ ANALYSIS │              │ ANALYSIS │              │ ANALYSIS │
   └──────────┘              └──────────┘              └──────────┘
```

The pair test is the fundamental unit. A single workspace succeeds trivially. The second workspace exposes: space collisions, bar item overlaps, stale bindings, window order reversals, space index renumbering, and state manifest conflicts.

---

## Principles

1. **Always test in pairs** &mdash; it is almost always the second workspace that collides with the first
2. **Same display** &mdash; deploy both workspaces to the same display to force space coexistence
3. **Use `--debug`** &mdash; every test run captures full yabai window/space dumps at each checkpoint
4. **Run analysis** &mdash; analysis.sh produces the temporal inventory; read every section, not just the summary
5. **Track window IDs** &mdash; the state manifest must own every WID; no orphans, no sharing
6. **Idempotent re-run** &mdash; running the same workspace again must produce ZERO discovery, ZERO creation
7. **Full cycle** &mdash; `yb down` + redeploy must produce identical results to the first deploy

---

## Instrumentation: two layers of observability

YB has two distinct output systems. They serve different purposes and go to different destinations. Understanding the difference is essential for debugging.

### Layer 1: Stderr log stream (`yb_log` / `bar_log`)

**What it is:** Human-readable timestamped text printed to stderr during every run.

**Destination:** Terminal stderr (`>&2`). Visible in the terminal as the run progresses. NOT written to any file.

**Format:**

```
[HH:MM:SS.mmm] message                    ← yb_log (from yb.sh / lib/common.sh)
[bar][HH:MM:SS.mmm] message               ← bar_log (from runners/bar.sh)
```

**Examples from a real run:**

```
[13:02:08.731] engine: yabai
[13:02:08.817] config: bar=standard bar_h=52 gap=10 pad=0,0,0,0
[13:02:09.163] state: validate=no_state
[13:02:09.498] workspace check: open=1
[13:02:10.179] switch: actual space=4 (from primary wid=51895)
[13:02:10.344] switch: bar items missing
[13:02:10.428] switch: repairing in-place on space=4 (have=2 expected=2)
[13:02:10.510] space-bsp: space=4 gap=10 pad=52,0,0,0 (bar=52)
[13:02:13.140] switch: creating bar items
[bar][13:02:13.821] start: style=standard display_id=3 space=4 label=ONTOSYS
[bar][13:02:14.983] binding ONTOSYS_* items to space=4
[13:02:15.514] switch: order check primary.x=2451.0000 secondary.x=726.0000
[13:02:15.596] switch: swapping — primary was on right
[13:02:15.711] state: written after repair
```

**What it tells you:**
- Which orchestration path was taken (CREATE / SWITCH / REPAIR / STATE FAST PATH)
- Every decision point with its input values (WIDs, space indices, display IDs)
- Timing between steps (spot slow operations or races)
- Bar operations (binding, rebinding, items-only mode)
- State manifest reads and writes

**Critical design:** Both `yb_log` and `bar_log` output to stderr via `>&2`. This is not cosmetic &mdash; it prevents log text from leaking into command substitutions. Before v0.5.1, `yb_log` went to stdout, which caused `$(some_function)` calls to capture log text into variables, corrupting `$SPACE_IDX` and bar labels. The stderr redirect is a safety invariant.

**How to capture:** When running tests via `bash yb.sh ontosys 3 --debug 2>&1`, stderr is merged into stdout so both the log stream and `--debug` output appear together. For log-only capture: `bash yb.sh ontosys 3 2>run.log`.

### Layer 2: Debug probe snapshots (`yb_debug`)

**What it is:** Full machine-readable JSON dumps of the ENTIRE yabai window/space/sketchybar state captured at specific checkpoints during a `--debug` run.

**Destination:** Individual JSON files in `log/debug/`. One file per checkpoint. Analysis.sh reads these files to produce the temporal inventory report.

**When active:** Only when `--debug` flag is passed. Without it, `yb_debug()` is a no-op (`: ;`).

**File naming convention:**

```
log/debug/{SESSION}_{LABEL}_{SEQ}_{STEP}.json

Examples:
  2026-02-15_13-02-05.516_ONTOSYS_01_config.json
  2026-02-15_13-02-05.516_ONTOSYS_02_state-validate.json
  2026-02-15_13-02-05.516_ONTOSYS_09_switch-done.json
  2026-02-15_13-02-28.642_PUFF_01_config.json
  2026-02-15_13-02-28.642_PUFF_10_done.json
```

| Component | Meaning |
|-----------|---------|
| `SESSION` | Timestamp when `yb.sh` started (shared across all probes in one run) |
| `LABEL` | Workspace label (e.g., ONTOSYS, PUFF) |
| `SEQ` | Zero-padded sequence number (01, 02, ...) |
| `STEP` | Checkpoint name (see checkpoint list below) |

**JSON structure of each probe file:**

```json
{
  "timestamp": "13:04:22.714",
  "label": "ONTOSYS",
  "step": "state-validate",
  "note": "result=intact",
  "space_idx": "4",
  "display": "3",
  "primary_wid": "51895",
  "secondary_wid": "52609",
  "sketchybar": {
    "running": true,
    "bar_height": "52",
    "badge_space": "4"
  },
  "windows": [ /* full yabai -m query --windows output */ ],
  "spaces":  [ /* full yabai -m query --spaces output */ ]
}
```

| Field | Source | Purpose |
|-------|--------|---------|
| `timestamp` | `python3 datetime` | Exact time this probe fired |
| `label` | `$LABEL` shell var | Which workspace this probe belongs to |
| `step` | first arg to `yb_debug` | Checkpoint name (used for ordering and coverage) |
| `note` | second arg to `yb_debug` | Free-form context string |
| `space_idx` | `$SPACE_IDX` shell var | Current target space index (empty if not yet resolved) |
| `display` | `$DISPLAY` shell var | Target display CGDirectDisplayID |
| `primary_wid` | `$PRIMARY_WID` shell var | Primary window ID (empty if not yet found) |
| `secondary_wid` | `$SECONDARY_WID` shell var | Secondary window ID (empty if not yet found) |
| `sketchybar.running` | `pgrep sketchybar` | Whether sketchybar process is alive |
| `sketchybar.bar_height` | `sketchybar --query bar` | Bar height at this moment |
| `sketchybar.badge_space` | `sketchybar --query ${LABEL}_badge` | Space the badge item is bound to (from `associated_space_mask` bitmask) |
| `windows` | `yabai -m query --windows` | **Full window dump** &mdash; every window with id, app, title, frame, space, display |
| `spaces` | `yabai -m query --spaces` | **Full space dump** &mdash; every space with index, display, uuid, is-visible, windows list |

**What it tells you that logs can't:** The `windows` array is the key. It captures the position, space, and identity of EVERY window on the system at that moment. By comparing consecutive probes, analysis.sh detects windows that moved between spaces, appeared (SPAWN), or disappeared (VANISH) &mdash; even if the orchestrator didn't log it.

### How the two layers relate

```
Layer 1 (log stream)               Layer 2 (debug probes)
━━━━━━━━━━━━━━━━━━━━               ━━━━━━━━━━━━━━━━━━━━━━
stderr text                         JSON files in log/debug/
every run                           only with --debug
tells you WHAT happened             tells you the FULL STATE at each point
human reads during run              analysis.sh reads after run
no window/space data                complete yabai + sketchybar dump
sequential narrative                point-in-time snapshots
```

Both fire at the same checkpoints. A `yb_log(...)` call and a `yb_debug(...)` call often sit next to each other in the code. The log line tells you the decision; the probe captures the state that led to it.

---

## Checkpoints

Debug probes fire at fixed points in the orchestration flow. The checkpoint name encodes which phase of the pipeline is active.

### Checkpoint sequence (canonical order)

```
 #  Checkpoint         Path        What just happened
──  ──────────────     ────────    ──────────────────────────────────────
 1  config             both        Layout resolved, app handlers loaded
 2  state-validate     both        State manifest checked against live state
 3  workspace-check    both*       app_code_is_open() checked (* skipped if state=intact)
 4  switch-locate      switch      Primary window found via yabai query
 5  switch-bsp         switch      Space BSP configured, space focused
 6  switch-primary     switch      Primary window confirmed/opened on space
 7  switch-secondary   switch      Secondary window confirmed/opened on space
 8  switch-bar         switch      Bar items created/rebound
 9  switch-done        switch      SWITCH complete — exit
10  pre-create         create      About to create virtual desktop
11  post-space         create      Desktop created, BSP configured
12  post-bar           create      Bar items created and bound
13  post-poll          create      Primary window found (after polling)
14  post-move          create      Windows moved to target space
15  post-layout        create      BSP layout settled, order enforced
16  done               create      CREATE complete — exit
```

**Path detection:** Analysis.sh infers which path was taken by which checkpoints fired:
- Has `switch-done` → **switch** (REPAIR or FAST PATH)
- Has `pre-create` but no `switch-done` → **create**
- Has `switch-locate` AND `pre-create` → **switch→create fallthrough** (display migration)
- Only `config` + `state-validate` + `switch-done` → **state fast path** (intact)

The state fast path (intact) is the ideal second run: only 3 probes, zero discovery.

---

## Analysis pipeline (`runners/analysis.sh`)

Analysis.sh reads the JSON probe files for a session and produces a multi-section report. It is invoked automatically at the end of every `--debug` run, or can be run standalone.

**Invocation:**
```bash
./runners/analysis.sh <session_id>     # specific session
./runners/analysis.sh --latest         # most recent session
./runners/analysis.sh --all            # all sessions combined
```

**Session resolution:** The session ID (e.g., `2026-02-15_13-02-05.516`) is the timestamp prefix. Analysis finds all JSON files with that prefix, sorts them, and processes them in order.

### Section-by-section breakdown

#### 1. Timeline

Lists every probe in chronological order with timestamp, label, step, space index, and note.

**What to check:** The path taken (create vs switch), the timing gaps between steps, whether space_idx appears at the right point.

#### 2. Checkpoint Coverage

For each workspace label, shows which checkpoints fired (✓) and which are missing (✗ MISSING). Analysis knows which checkpoints are expected for each path type and only flags MISSING for expected ones.

**What to check:** For a switch path, you expect config → state-validate → switch-* → switch-done. For create, you expect config → workspace-check → pre-create → post-* → done. Missing checkpoints mean the code skipped a step or crashed.

#### 3. Window Travel

The core temporal inventory. A matrix showing every non-sticky window's space assignment at every checkpoint. Columns are checkpoints, rows are window IDs.

**How it works:** For each probe file, analysis extracts every window from the `windows` array and records its `.space` value. Windows that don't exist in a probe show `·` (not yet spawned or vanished). Windows that changed space between consecutive probes show `→s5` (moved to space 5).

**What to check:**
- Windows owned by workspace A stay on A's space throughout
- Windows owned by workspace B stay on B's space throughout
- No window moves during SWITCH/REPAIR (moves only during CREATE step 4b)
- New WIDs (`·` → `sN`) only appear between post-bar and post-poll (the app open window)

#### 4. Anomalies

Diff-based detection between consecutive probes. For each pair of adjacent snapshots, analysis compares the window lists and flags:

| Event | Meaning | When it's OK |
|-------|---------|--------------|
| `SPAWN wid=N (App) on sN` | Window appeared that wasn't in the previous probe | During CREATE, between post-bar and post-poll (apps being opened) |
| `MOVED wid=N (App) sN → sN` | Window changed space between probes | During CREATE, between post-poll and post-move (step 4b moves) |
| `VANISH wid=N (App)` | Window disappeared between probes | During `yb down` or close operations |

**What to check:** SPAWNs during SWITCH/REPAIR are bugs (no new windows should be created). MOVEs during SWITCH are bugs (windows should already be in place). Any VANISH during normal operation is suspicious.

#### 5. Shared Windows

Checks whether any window ID is claimed by multiple workspace labels. A WID should belong to exactly one workspace. This catches the case where two workspaces grab the same window (e.g., both find the same Code window by title match).

**How it works:** For each label's final snapshot, collects all WIDs on that label's space. Also checks `secondary_wid` across all snapshots. If the same WID appears under different labels, it's flagged.

#### 5b. Merged Workspaces

Checks whether any space index has multiple workspace labels assigned to it. Two workspaces should never end up on the same space.

**How it works:** For each label, reads `space_idx` from its final snapshot. If two labels have the same space_idx, flags as CRITICAL.

#### 6. Window Order

Checks that primary window (Code) is to the left of secondary window (iTerm) in the final snapshot.

**How it works:** Reads `primary_wid` and `secondary_wid` from the final snapshot, looks up their `.frame.x` in the `windows` array, compares. primary.x < secondary.x = correct.

#### 7. Bar Health

Tracks sketchybar state across checkpoints using the `sketchybar` object embedded in each probe. Shows running status, bar height, and which space the badge item is bound to.

**How it works:** The `badge_space` field comes from the probe's live sketchybar query: `sketchybar --query ${LABEL}_badge` → `associated_space_mask` bitmask → decoded to space number. If badge_space doesn't match space_idx, items are bound to the wrong space.

#### 7b. State Manifest

Reads `state/manifest.json` and shows each workspace entry with space index, UUID prefix, app/WID pairs, and liveness (queries yabai to check if the WID still exists).

#### 8. Sketchybar Config (live)

Live query of the running sketchybar instance at analysis time. Shows bar-level config (position, height, color) and per-item details (drawing state, associated_space, display) for all 7 items per workspace.

**How it works:** Runs `sketchybar --query bar` and `sketchybar --query ${LABEL}_${suffix}` for each of the 7 suffixes (badge, label, path, code, term, folder, close). Decodes the `associated_space_mask` bitmask for each item.

#### 8b. Bar Sanity

Live checks that detect the three failure classes that v0.6.1 was built to catch:

1. **Unbound items** &mdash; badge item has `associated_space_mask=0`, meaning items appear on ALL spaces (the overlap bug). Detected by checking each label's badge mask.

2. **Duplicate bindings** &mdash; two different labels bound to the same space. Detected by collecting the decoded space from each label's badge and checking for duplicates.

3. **Label contamination** &mdash; path item's label value contains log text (`[bar]`, `workspace check`, timestamp patterns) or unparsed JSON (`{`, `":`). Detected by running string pattern matches against the live `label.value` from `sketchybar --query ${LABEL}_path`.

#### 9. Summary

Total snapshot count, labels found, anomaly count, and final space/WID for each workspace.

---

## Test scenarios

### T1. Clean pair deploy (CREATE + CREATE)

**Precondition:** `yb down` (clean slate, no state manifest, services stopped)

**Sequence:**
```bash
yb down
yb <workspace-A> <display> --debug
yb <workspace-B> <display> --debug
```

**Expected:**
| Check | Criterion |
|-------|-----------|
| Path A | `no_state` → CREATE (no existing workspace) |
| Path B | `no_state` → CREATE (no existing workspace) |
| Spaces | A and B on different space indices |
| Windows | A owns 2 WIDs (primary+secondary), B owns 2 different WIDs |
| Bar items | A items bound to A's space, B items bound to B's space |
| State manifest | Two entries, different space UUIDs, all WIDs alive |
| Window order | Primary.x < Secondary.x for both |
| Shared windows | Zero (no WID appears in both workspaces) |
| Bar Sanity | No overlaps, no unbound items, no label contamination |

**Failure modes caught:** space collision, bar overlap, stale plist reuse, window landing on wrong space.

---

### T2. Idempotent re-run (STATE FAST PATH)

**Precondition:** T1 completed successfully (both workspaces deployed)

**Sequence:**
```bash
yb <workspace-A> <display> --debug
yb <workspace-B> <display> --debug
```

**Expected:**
| Check | Criterion |
|-------|-----------|
| Path A | `intact` → STATE FAST PATH |
| Path B | `intact` → STATE FAST PATH |
| Snapshots | Exactly 3 per workspace (config, state-validate, switch-done) |
| Discovery | ZERO yabai window queries beyond state validation |
| Windows | No new WIDs spawned, no windows moved |
| Bar items | Already bound, no rebinding |
| Space focus | Correct space focused (not empty) |

**Failure modes caught:** subshell variable loss (v0.6.1 bug), state validate returning wrong result, unnecessary CREATE fallthrough.

---

### T3. Full reset + redeploy (DOWN + CREATE + CREATE)

**Precondition:** T2 completed successfully

**Sequence:**
```bash
yb down
yb <workspace-A> <display> --debug
yb <workspace-B> <display> --debug
```

**Expected:** Same as T1, but validates:
| Check | Criterion |
|-------|-----------|
| State cleared | `yb down` removed manifest.json |
| Services restarted | yabai + sketchybar started fresh |
| New WIDs | All window IDs differ from T1 (old windows were closed) |
| Clean bar | No leftover items from T1 |

**Failure modes caught:** stale state after restart, window close failures, bar item leaks.

---

### T4. Repair path (PARTIAL DESTRUCTION)

**Precondition:** T1 completed successfully

**Sequence:**
1. Manually close ONE window (e.g., close iTerm2 for workspace A)
2. Run `yb <workspace-A> <display> --debug`

**Expected:**
| Check | Criterion |
|-------|-----------|
| State result | `secondary_dead` (or `primary_dead`) |
| Path | Falls through to REPAIR, not CREATE |
| Repair action | Opens replacement window, moves to correct space |
| State updated | New WID written for the replaced window |
| Other workspace | Unaffected (workspace B stays intact) |

**Failure modes caught:** dead WID detection, repair opening window on wrong space, state not updated after repair.

---

### T5. Bar-only repair (BAR DESTRUCTION)

**Precondition:** T1 completed successfully

**Sequence:**
1. Remove bar items manually: `sketchybar --remove <LABEL>_badge` (etc.)
2. Run `yb <workspace-A> <display> --debug`

**Expected:**
| Check | Criterion |
|-------|-----------|
| State result | `bar_missing` |
| Path | Creates bar items, binds to correct space, exits |
| Windows | Untouched (no reopening, no moving) |
| Bar items | Recreated and bound to correct space |

---

### T6. Window order reversal

**Precondition:** T1 completed successfully

**Sequence:**
1. Manually swap windows (drag primary to right side)
2. Run `yb <workspace-A> <display> --debug`

**Expected:**
| Check | Criterion |
|-------|-----------|
| State result | `order_wrong` |
| Path | Swaps windows via `yabai -m window --swap`, exits |
| Final order | Primary.x < Secondary.x |

---

### T7. Cross-cycle switching

**Precondition:** T1 completed successfully

**Sequence:**
```bash
yb <workspace-A> <display> --debug    # switch to A
yb <workspace-B> <display> --debug    # switch to B
yb <workspace-A> <display> --debug    # switch back to A
yb <workspace-B> <display> --debug    # switch back to B
```

**Expected:**
| Check | Criterion |
|-------|-----------|
| All runs | `intact` → STATE FAST PATH (3 snapshots each) |
| Space focus | Alternates between A's space and B's space |
| No creation | Zero new windows, zero bar recreations |
| Bar items | Both sets remain bound to their respective spaces |

**Failure modes caught:** space rebinding on switch, stale bar bindings, focus failures.

---

## Analysis checklist

After every `--debug` run, analysis.sh produces sections that MUST be checked:

| Section | What to verify |
|---------|----------------|
| **Timeline** | Correct path taken (create/switch), correct checkpoints hit |
| **Checkpoint Coverage** | No unexpected MISSING checkpoints for the path taken |
| **Window Travel** | No window changed space unexpectedly; new WIDs only during CREATE |
| **Anomalies** | Only expected SPAWNs during CREATE; zero anomalies during SWITCH |
| **Shared Windows** | Zero &mdash; no WID claimed by multiple workspaces |
| **Merged Workspaces** | Zero &mdash; no two labels on the same space |
| **Window Order** | Primary.x < Secondary.x for all workspaces |
| **Bar Health** | Running=true, correct space binding at every checkpoint |
| **State Manifest** | Correct WIDs, UUIDs, liveness=alive for all entries |
| **Sketchybar Config** | All 7 items per workspace, drawing=on, correct space binding |
| **Bar Sanity** | No overlaps, no unbound items, no label contamination |

### Red flags in analysis output

These indicate bugs, not just warnings:

- `SPAWN` during a SWITCH path (window opened when it shouldn't have been)
- `MOVED` of a window between spaces (window drifted or was moved incorrectly)
- `VANISH` of a window during normal operation
- Shared Windows: any entry at all
- Merged Workspaces: any entry at all
- `STALE` in Bar Health (items bound to wrong space)
- `FAIL` in Bar Sanity (overlaps, unbound items, contamination)
- State Manifest: `stale` liveness for any entry
- Window Order: `REVERSED` for any workspace
- Checkpoint Coverage: MISSING for expected checkpoints

---

## Standard test pair

The default test pair used throughout v0.5.x and v0.6.x development:

```
Workspace A:  ontosys    display: 3
Workspace B:  puff       display: 3
```

Both use `claudedev` layout (tile mode, standard bar, Code + iTerm2). Same display forces space coexistence and bar item collision testing.

### Full standard test run

```bash
# Cycle 1: clean deploy
yb down
yb ontosys 3 --debug
yb puff 3 --debug

# Cycle 2: idempotent re-run
yb ontosys 3 --debug
yb puff 3 --debug

# Cycle 3: full reset
yb down
yb ontosys 3 --debug
yb puff 3 --debug

# Cycle 4: rapid switching
yb ontosys 3 --debug
yb puff 3 --debug
yb ontosys 3 --debug
yb puff 3 --debug
```

### Pass criteria

| Cycle | Workspace A | Workspace B | Anomalies |
|-------|-------------|-------------|-----------|
| 1 | CREATE or REPAIR | CREATE | 0 (except expected SPAWNs) |
| 2 | intact (3 snapshots) | intact (3 snapshots) | 0 |
| 3 | CREATE or REPAIR | CREATE | 0 (except expected SPAWNs) |
| 4 | intact (3 snapshots) x2 | intact (3 snapshots) x2 | 0 |

Bar Sanity: PASS on every cycle.

---

## Bugs caught by this methodology

| Version | Bug | Caught by |
|---------|-----|-----------|
| v0.5.0 | REBUILD fallthrough &mdash; second run closed everything, fell through to CREATE | T2 (idempotent re-run showed full CREATE instead of fast path) |
| v0.5.1 | Log stdout contamination &mdash; `yb_log` output leaked into `$SPACE_IDX` | T1 analysis: Bar Sanity detected corrupted path label |
| v0.6.0 | Subshell variable loss &mdash; `_SV_SPACE_IDX` empty after `$()` | T2: `space=` empty in log, `focus-space: WARN tgt=(pos=-1)` |
| v0.6.1 | `no_state` not echoed &mdash; `yb_state_validate` returned empty | T1: `validate=` instead of `validate=no_state` in log |

---

## Claude skill integration

This test methodology can be packaged as a Claude Code skill for repeatable execution.

### Skill definition

Location: `~/.claude/skills/yb-test.md` (or project-local `.claude/skills/yb-test.md`)

```markdown
# yb-test

Run the YB standard pair test sequence.

## Usage
/yb-test              # full 4-cycle test
/yb-test quick        # cycle 1+2 only
/yb-test cycle <N>    # run specific cycle

## Behavior

1. Read SPEC.TESTING.md to load test definitions and pass criteria
2. Execute the test cycles using Bash tool
3. After each cycle, read the analysis output carefully
4. Check every section against the analysis checklist in SPEC.TESTING.md
5. Report results in a summary table:
   - Cycle number
   - Path taken per workspace (CREATE/REPAIR/intact)
   - Snapshot count
   - Anomaly count
   - Bar Sanity result (PASS/FAIL)
6. If any failure is detected, stop and report the exact section and values
7. Use the standard test pair: ontosys + puff on display 3
```

### Skill prompt structure

The skill should:

1. **Read SPEC.TESTING.md** first to load the test definitions and pass criteria
2. **Execute cycles sequentially** &mdash; each cycle's output feeds into the next cycle's precondition check
3. **Parse analysis output** &mdash; extract key values from each section (path taken, snapshot count, anomaly count, bar sanity)
4. **Compare against criteria** &mdash; match actual vs expected from the scenario tables
5. **Produce structured output** &mdash; summary table + any failures with exact log lines

### Key design choices

- **Not a bash script** &mdash; the skill is a Claude prompt, not automation. The AI reads and interprets the analysis output, catching subtle failures that grep can't
- **Sequential, not parallel** &mdash; each cycle depends on the previous cycle's state
- **Stop on first failure** &mdash; don't continue running cycles if one fails; diagnose first
- **Full context** &mdash; the skill has access to all YB source files and can cross-reference analysis output against the actual code to diagnose root causes

### Example skill output

```
YB Pair Test Results
====================

Cycle 1 (clean deploy):
  ONTOSYS: REPAIR (no_state, bar missing)  9 snapshots  0 anomalies
  PUFF:    CREATE                          10 snapshots  2 anomalies (expected SPAWNs)
  Bar Sanity: PASS
  State: ONTOSYS=s4 PUFF=s5 (both alive)

Cycle 2 (idempotent):
  ONTOSYS: intact                          3 snapshots   0 anomalies
  PUFF:    intact                          3 snapshots   0 anomalies
  Bar Sanity: PASS

Cycle 3 (full reset):
  ONTOSYS: REPAIR (no_state, iTerm missing) 9 snapshots  1 anomaly (expected SPAWN)
  PUFF:    CREATE                           10 snapshots  2 anomalies (expected SPAWNs)
  Bar Sanity: PASS

Cycle 4 (rapid switching):
  4x intact                                3 snapshots each  0 anomalies
  Bar Sanity: PASS

RESULT: ALL PASS
```
