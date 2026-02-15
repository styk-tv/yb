# YB Testing Specification

Pair-based test methodology for validating workspace orchestration. Workspaces collide at the second deployment &mdash; the first one always works. This spec defines the test sequences that catch real failures.

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
- `MOVE` of a window between spaces (window drifted or was moved incorrectly)
- `STEAL` (WID claimed by different workspace)
- `bar_stale` or `STALE` in Bar Health (items bound to wrong space)
- `FAIL` in Bar Sanity (overlaps, unbound items, contamination)
- Shared Windows: any entry at all
- Merged Workspaces: any entry at all
- State Manifest: `stale` liveness for any entry

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

1. Execute the test cycles using Bash tool
2. After each cycle, read the analysis output carefully
3. Check every section against the analysis checklist in SPEC.TESTING.md
4. Report results in a summary table:
   - Cycle number
   - Path taken per workspace (CREATE/REPAIR/intact)
   - Snapshot count
   - Anomaly count
   - Bar Sanity result (PASS/FAIL)
5. If any failure is detected, stop and report the exact section and values
6. Use the standard test pair: ontosys + puff on display 3
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
