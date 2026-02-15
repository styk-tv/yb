#!/bin/bash
# FILE: runners/analysis.sh
# Analyze a --debug session: track window travel, element spawning, space changes
#
# Usage:
#   ./runners/analysis.sh <session_id>     # analyze specific session
#   ./runners/analysis.sh --latest          # analyze most recent session
#   ./runners/analysis.sh --all             # analyze all sessions combined

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUG_DIR="$REPO_ROOT/log/debug"

if [ ! -d "$DEBUG_DIR" ]; then
    echo "No debug directory found at $DEBUG_DIR"
    exit 1
fi

# Resolve session
MULTI_SESSION=0
if [ "$1" = "--all" ]; then
    FILES=($(ls "$DEBUG_DIR"/*.json 2>/dev/null | sort))
    MULTI_SESSION=1
    SESSION_LABEL="ALL SESSIONS"
elif [ "$1" = "--latest" ] || [ -z "$1" ]; then
    SESSION=$(ls "$DEBUG_DIR"/*.json 2>/dev/null | sed 's|.*/||' | cut -d'_' -f1-3 | sort -u | tail -1)
    FILES=($(ls "$DEBUG_DIR/${SESSION}"_*.json 2>/dev/null | sort))
    SESSION_LABEL="$SESSION"
else
    SESSION="$1"
    FILES=($(ls "$DEBUG_DIR/${SESSION}"_*.json 2>/dev/null | sort))
    SESSION_LABEL="$SESSION"
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No debug files found"
    exit 1
fi

# Temp file for anomaly collection (avoids subshell counter problem)
ANOMALY_FILE=$(mktemp)
trap "rm -f $ANOMALY_FILE" EXIT

# --- Canonical checkpoint order ---
CHECKPOINTS="config state-validate workspace-check switch-locate switch-bsp switch-bar switch-focus switch-secondary switch-done pre-create post-space post-bar post-poll post-move post-layout done"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  YB Debug Analysis                                          ║"
echo "║  Session: $SESSION_LABEL"
echo "║  Snapshots: ${#FILES[@]}"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────────────────────
# 1. TIMELINE — every checkpoint with timestamp, label, step
# ──────────────────────────────────────────────────────────────
echo "┌─ Timeline ─────────────────────────────────────────────────────┐"
echo "│"
printf "│  %-4s  %-10s  %-12s  %-20s  %-8s  %s\n" "#" "TIME" "LABEL" "STEP" "SPACE" "NOTE"
printf "│  %-4s  %-10s  %-12s  %-20s  %-8s  %s\n" "──" "────────" "──────────" "──────────────────" "──────" "──────────────────────"

GLOBAL_SEQ=0
for f in "${FILES[@]}"; do
    GLOBAL_SEQ=$((GLOBAL_SEQ + 1))
    _ts=$(jq -r '.timestamp // "—"' "$f")
    _label=$(jq -r '.label // "—"' "$f")
    _step=$(jq -r '.step // "—"' "$f")
    _space=$(jq -r '.space_idx // "—"' "$f")
    _note=$(jq -r '.note // ""' "$f")
    printf "│  %-4s  %-10s  %-12s  %-20s  %-8s  %s\n" \
        "$(printf '%02d' $GLOBAL_SEQ)" "$_ts" "$_label" "$_step" "$_space" "$_note"
done
echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 2. CHECKPOINT COVERAGE — which steps fired per label
# ──────────────────────────────────────────────────────────────
echo "┌─ Checkpoint Coverage ────────────────────────────────────────┐"
echo "│"

# Get unique labels
LABELS=$(for f in "${FILES[@]}"; do jq -r '.label // ""' "$f"; done | sort -u)

for lbl in $LABELS; do
    [ -z "$lbl" ] && continue
    echo "│  $lbl:"
    FIRED_STEPS=$(for f in "${FILES[@]}"; do
        _l=$(jq -r '.label // ""' "$f")
        [ "$_l" = "$lbl" ] && jq -r '.step // ""' "$f"
    done)

    # Detect which path was taken:
    # - pure switch: has switch-bsp/switch-done, no pre-create
    # - pure create: has pre-create, no switch-locate
    # - mixed (switch→create fallthrough): has switch-locate AND pre-create
    _has_switch_done=$(echo "$FIRED_STEPS" | grep -c "switch-done")
    _has_create=$(echo "$FIRED_STEPS" | grep -c "pre-create\|post-space")
    _has_switch_locate=$(echo "$FIRED_STEPS" | grep -c "switch-locate")

    if [ "$_has_switch_done" -gt 0 ]; then
        _PATH_LABEL="switch"
    elif [ "$_has_switch_locate" -gt 0 ] && [ "$_has_create" -gt 0 ]; then
        _PATH_LABEL="switch→create (fallthrough)"
    elif [ "$_has_create" -gt 0 ]; then
        _PATH_LABEL="create"
    else
        _PATH_LABEL="unknown"
    fi
    echo "│    path: $_PATH_LABEL"

    step_num=0
    for ckpt in $CHECKPOINTS; do
        step_num=$((step_num + 1))
        if echo "$FIRED_STEPS" | grep -qx "$ckpt"; then
            printf "│    %2d. %-20s  ✓\n" "$step_num" "$ckpt"
        else
            case "$_PATH_LABEL" in
                switch)
                    # Pure switch: only switch-* and config/workspace-check expected
                    case "$ckpt" in
                        switch-*|config|workspace-check)
                            printf "│    %2d. %-20s  ✗ MISSING\n" "$step_num" "$ckpt" ;;
                    esac
                    ;;
                create)
                    # Pure create: only create-path steps expected
                    case "$ckpt" in
                        config|workspace-check|pre-create|post-space|post-bar|post-poll|post-move|post-layout|done)
                            printf "│    %2d. %-20s  ✗ MISSING\n" "$step_num" "$ckpt" ;;
                    esac
                    ;;
                "switch→create (fallthrough)")
                    # Mixed: switch-locate fired then fell to create — switch-bsp..switch-done are NOT expected
                    case "$ckpt" in
                        config|workspace-check|switch-locate|pre-create|post-space|post-bar|post-poll|post-move|post-layout|done)
                            printf "│    %2d. %-20s  ✗ MISSING\n" "$step_num" "$ckpt" ;;
                    esac
                    ;;
                *)
                    printf "│    %2d. %-20s  ?\n" "$step_num" "$ckpt"
                    ;;
            esac
        fi
    done
    echo "│"
done
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 3. WINDOW TRAVEL — track each non-sticky window across snapshots
# ──────────────────────────────────────────────────────────────
echo "┌─ Window Travel ────────────────────────────────────────────────┐"
echo "│"

# Collect all unique wid|app pairs
ALL_WIDS=$(for f in "${FILES[@]}"; do
    jq -r '.windows[]? | select(.["is-sticky"] == false) | "\(.id)|\(.app)|\(.title[:30])"' "$f" 2>/dev/null
done | sort -t'|' -k1 -n -u)

if [ -z "$ALL_WIDS" ]; then
    echo "│  No non-sticky windows found"
else
    # Build compact column headers: seq:step (truncated)
    HDRS=()
    for f in "${FILES[@]}"; do
        _step=$(jq -r '.step // "?"' "$f")
        _label=$(jq -r '.label // "?"' "$f")
        # Shorten step names
        _short="${_step}"
        case "$_step" in
            workspace-check) _short="ws-chk" ;;
            switch-locate) _short="sw-loc" ;;
            switch-bsp) _short="sw-bsp" ;;
            switch-bar) _short="sw-bar" ;;
            switch-focus) _short="sw-foc" ;;
            switch-secondary) _short="sw-sec" ;;
            switch-done) _short="sw-done" ;;
            pre-create) _short="pre-crt" ;;
            post-space) _short="p-space" ;;
            post-bar) _short="p-bar" ;;
            post-poll) _short="p-poll" ;;
            post-move) _short="p-move" ;;
            post-layout) _short="p-lay" ;;
        esac
        HDRS+=("${_label:0:4}:${_short}")
    done

    # Header row
    printf "│  %-8s %-12s  " "WID" "APP"
    for h in "${HDRS[@]}"; do
        printf "%-11s" "$h"
    done
    echo ""
    printf "│  ──────── ────────────  "
    for h in "${HDRS[@]}"; do printf "─────────── "; done
    echo ""

    # Data rows
    echo "$ALL_WIDS" | while IFS='|' read -r wid app title; do
        printf "│  %-8s %-12s  " "$wid" "$app"
        _prev_space=""
        for f in "${FILES[@]}"; do
            _space=$(jq -r --argjson wid "$wid" \
                '.windows[]? | select(.id == $wid) | .space' "$f" 2>/dev/null)
            if [ -z "$_space" ]; then
                printf "%-11s" "·"
            elif [ -n "$_prev_space" ] && [ "$_space" != "$_prev_space" ]; then
                # Highlight space change with arrow
                printf "%-11s" "→s${_space}"
            else
                printf "%-11s" "s${_space}"
            fi
            _prev_space="$_space"
        done
        echo ""
    done
fi
echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 4. ANOMALY DETECTION — moves, spawns, vanishes between steps
# ──────────────────────────────────────────────────────────────
echo "┌─ Anomalies ────────────────────────────────────────────────────┐"
echo "│"

PREV_FILE=""
PREV_NUM=0
for f in "${FILES[@]}"; do
    PREV_NUM=$((PREV_NUM + 1))
    if [ -n "$PREV_FILE" ]; then
        _prev_step=$(jq -r '.step' "$PREV_FILE")
        _curr_step=$(jq -r '.step' "$f")
        _prev_label=$(jq -r '.label // ""' "$PREV_FILE")
        _curr_label=$(jq -r '.label // ""' "$f")
        _tag="$(printf '%02d' $((PREV_NUM-1))):${_prev_step} → $(printf '%02d' $PREV_NUM):${_curr_step}"

        # Windows that changed space
        jq -r '.windows[]? | select(.["is-sticky"] == false) | "\(.id)|\(.space)|\(.app)"' "$PREV_FILE" 2>/dev/null | \
        while IFS='|' read -r wid prev_space app; do
            curr_space=$(jq -r --argjson wid "$wid" '.windows[]? | select(.id == $wid) | .space' "$f" 2>/dev/null)
            if [ -n "$curr_space" ] && [ "$curr_space" != "$prev_space" ]; then
                echo "│  MOVED   wid=$wid ($app)  s${prev_space} → s${curr_space}  [$_tag]" | tee -a "$ANOMALY_FILE"
            fi
        done

        # Windows that appeared
        jq -r '.windows[]? | select(.["is-sticky"] == false) | .id' "$f" 2>/dev/null | while read -r wid; do
            prev_exists=$(jq -r --argjson wid "$wid" '.windows[]? | select(.id == $wid) | .id' "$PREV_FILE" 2>/dev/null)
            if [ -z "$prev_exists" ]; then
                app=$(jq -r --argjson wid "$wid" '.windows[]? | select(.id == $wid) | .app' "$f" 2>/dev/null)
                space=$(jq -r --argjson wid "$wid" '.windows[]? | select(.id == $wid) | .space' "$f" 2>/dev/null)
                echo "│  SPAWN   wid=$wid ($app) on s${space}  [$_tag]" | tee -a "$ANOMALY_FILE"
            fi
        done

        # Windows that disappeared
        jq -r '.windows[]? | select(.["is-sticky"] == false) | .id' "$PREV_FILE" 2>/dev/null | while read -r wid; do
            curr_exists=$(jq -r --argjson wid "$wid" '.windows[]? | select(.id == $wid) | .id' "$f" 2>/dev/null)
            if [ -z "$curr_exists" ]; then
                app=$(jq -r --argjson wid "$wid" '.windows[]? | select(.id == $wid) | .app' "$PREV_FILE" 2>/dev/null)
                echo "│  VANISH  wid=$wid ($app)  [$_tag]" | tee -a "$ANOMALY_FILE"
            fi
        done
    fi
    PREV_FILE="$f"
done

ANOMALY_COUNT=$(wc -l < "$ANOMALY_FILE" 2>/dev/null | tr -d ' ')
if [ "$ANOMALY_COUNT" = "0" ] || [ -z "$ANOMALY_COUNT" ]; then
    echo "│  No anomalies detected"
fi
echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 5. SHARED WINDOW CHECK — same wid claimed by multiple labels
# ──────────────────────────────────────────────────────────────
echo "┌─ Shared Windows ───────────────────────────────────────────────┐"
echo "│"

# For each label's final snapshot, check what wids are on its space
SHARED_FOUND=0
declare -A WID_OWNERS 2>/dev/null || true

# Get final snapshot per label
for lbl in $LABELS; do
    [ -z "$lbl" ] && continue
    LAST_FILE=""
    for f in "${FILES[@]}"; do
        _l=$(jq -r '.label // ""' "$f")
        [ "$_l" = "$lbl" ] && LAST_FILE="$f"
    done
    [ -z "$LAST_FILE" ] && continue

    _space=$(jq -r '.space_idx // ""' "$LAST_FILE")
    [ -z "$_space" ] || [ "$_space" = "null" ] && continue

    # Get non-sticky wids on this label's space
    jq -r --argjson sp "$_space" \
        '.windows[]? | select(.["is-sticky"] == false and .space == ($sp | tonumber)) | "\(.id)|\(.app)"' \
        "$LAST_FILE" 2>/dev/null | while IFS='|' read -r wid app; do
        echo "$wid|$app|$lbl"
    done
done | sort -t'|' -k1 -n > "${ANOMALY_FILE}.shared"

# Also check: same wid appearing in different labels' operations
# Look at secondary_wid across all snapshots (deduplicate per wid+label)
for f in "${FILES[@]}"; do
    _label=$(jq -r '.label // ""' "$f")
    _sec_wid=$(jq -r '.secondary_wid // ""' "$f")
    [ -n "$_sec_wid" ] && [ "$_sec_wid" != "" ] && [ "$_sec_wid" != "null" ] && \
        echo "$_sec_wid|secondary|$_label"
done | sort -u > "${ANOMALY_FILE}.claimed"

# Find wids claimed by multiple DIFFERENT labels (not same label repeated)
_DUP_WIDS=$(cut -d'|' -f1,3 "${ANOMALY_FILE}.claimed" 2>/dev/null | cut -d'|' -f1 | sort | uniq -d)
if [ -n "$_DUP_WIDS" ]; then
    for _dwid in $_DUP_WIDS; do
        _owners=$(grep "^${_dwid}|" "${ANOMALY_FILE}.claimed" | cut -d'|' -f3 | sort -u | tr '\n' '+' | sed 's/+$//')
        echo "│  ⚠ wid=$_dwid claimed by MULTIPLE labels: $_owners"
        SHARED_FOUND=1
    done
fi

if [ "$SHARED_FOUND" -eq 0 ]; then
    echo "│  No shared windows detected"
fi
rm -f "${ANOMALY_FILE}.shared" "${ANOMALY_FILE}.claimed"
echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 5b. MERGED WORKSPACES — multiple labels on same space
# ──────────────────────────────────────────────────────────────
echo "┌─ Merged Workspaces ────────────────────────────────────────────┐"
echo "│"

MERGED_FOUND=0
# Get final space for each label
for lbl in $LABELS; do
    [ -z "$lbl" ] && continue
    LAST_FILE=""
    for f in "${FILES[@]}"; do
        _l=$(jq -r '.label // ""' "$f")
        [ "$_l" = "$lbl" ] && LAST_FILE="$f"
    done
    [ -z "$LAST_FILE" ] && continue
    _space=$(jq -r '.space_idx // ""' "$LAST_FILE")
    [ -z "$_space" ] || [ "$_space" = "null" ] && continue
    echo "$_space|$lbl"
done | sort -t'|' -k1 -n > "${ANOMALY_FILE}.spaces"

# Find spaces with multiple labels
_DUP_SPACES=$(cut -d'|' -f1 "${ANOMALY_FILE}.spaces" 2>/dev/null | sort | uniq -d)
if [ -n "$_DUP_SPACES" ]; then
    for _sp in $_DUP_SPACES; do
        _labels=$(grep "^${_sp}|" "${ANOMALY_FILE}.spaces" | cut -d'|' -f2 | sort | tr '\n' '+' | sed 's/+$//')
        echo "│  🔴 CRITICAL: Multiple workspaces on space $_sp → $_labels"
        MERGED_FOUND=1
    done
fi

if [ "$MERGED_FOUND" -eq 0 ]; then
    echo "│  ✓ All workspaces on separate spaces"
fi
rm -f "${ANOMALY_FILE}.spaces"
echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 6. WINDOW ORDER — check primary (left) vs secondary (right)
# ──────────────────────────────────────────────────────────────
echo "┌─ Window Order ──────────────────────────────────────────────────┐"
echo "│"

for lbl in $LABELS; do
    [ -z "$lbl" ] && continue
    LAST_FILE=""
    for f in "${FILES[@]}"; do
        _l=$(jq -r '.label // ""' "$f")
        [ "$_l" = "$lbl" ] && LAST_FILE="$f"
    done
    [ -z "$LAST_FILE" ] && continue

    _pwid=$(jq -r '.primary_wid // ""' "$LAST_FILE")
    _swid=$(jq -r '.secondary_wid // ""' "$LAST_FILE")

    if [ -z "$_pwid" ] || [ "$_pwid" = "—" ] || [ "$_pwid" = "null" ] || \
       [ -z "$_swid" ] || [ "$_swid" = "—" ] || [ "$_swid" = "null" ]; then
        echo "│  $lbl: — (primary=${_pwid:-?} secondary=${_swid:-?} — missing wid, can't check)"
        continue
    fi

    # Look up frame.x for each wid in the windows array of the final snapshot
    _px=$(jq -r --argjson wid "$_pwid" '.windows[]? | select(.id == $wid) | .frame.x' "$LAST_FILE" 2>/dev/null)
    _sx=$(jq -r --argjson wid "$_swid" '.windows[]? | select(.id == $wid) | .frame.x' "$LAST_FILE" 2>/dev/null)

    if [ -z "$_px" ] || [ -z "$_sx" ]; then
        echo "│  $lbl: — (primary wid=$_pwid x=${_px:-?}, secondary wid=$_swid x=${_sx:-?} — not in snapshot)"
        continue
    fi

    _px_int="${_px%.*}"
    _sx_int="${_sx%.*}"

    if [ "$_px_int" -lt "$_sx_int" ] 2>/dev/null; then
        echo "│  $lbl: ✓ correct (primary wid=$_pwid x=$_px  <  secondary wid=$_swid x=$_sx)"
    elif [ "$_px_int" -gt "$_sx_int" ] 2>/dev/null; then
        echo "│  $lbl: ✗ REVERSED (primary wid=$_pwid x=$_px  >  secondary wid=$_swid x=$_sx)" | tee -a "$ANOMALY_FILE"
    else
        echo "│  $lbl: ? same x (primary wid=$_pwid x=$_px  ==  secondary wid=$_swid x=$_sx)"
    fi
done

echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 7. BAR HEALTH — sketchybar process + item bindings across snapshots
# ──────────────────────────────────────────────────────────────
echo "┌─ Bar Health ────────────────────────────────────────────────────┐"
echo "│"

# Check if sketchybar data is present in any snapshot
_HAS_SBAR_DATA=0
for f in "${FILES[@]}"; do
    _running=$(jq -r '.sketchybar.running // ""' "$f" 2>/dev/null)
    [ "$_running" = "true" ] || [ "$_running" = "false" ] && { _HAS_SBAR_DATA=1; break; }
done

if [ "$_HAS_SBAR_DATA" -eq 0 ]; then
    echo "│  No sketchybar data in snapshots (run with updated --debug to capture)"
else
    for lbl in $LABELS; do
        [ -z "$lbl" ] && continue
        echo "│  $lbl:"

        _prev_space_bind=""
        for f in "${FILES[@]}"; do
            _l=$(jq -r '.label // ""' "$f")
            [ "$_l" != "$lbl" ] && continue

            _step=$(jq -r '.step // "?"' "$f")
            _running=$(jq -r '.sketchybar.running // "?"' "$f" 2>/dev/null)
            _height=$(jq -r '.sketchybar.bar_height // "?"' "$f" 2>/dev/null)
            _space_idx=$(jq -r '.space_idx // "?"' "$f")

            # Check badge item binding (simplified: badge_space field from debug probe)
            _badge_bind=$(jq -r '.sketchybar.badge_space // "missing"' "$f" 2>/dev/null)

            # Detect mismatch: items bound to wrong space
            _status="ok"
            if [ "$_running" = "false" ]; then
                _status="DEAD"
                echo "│    $_step: ✗ sketchybar NOT RUNNING" | tee -a "$ANOMALY_FILE"
            elif [ "$_badge_bind" = "missing" ]; then
                _status="no-items"
            elif [ -n "$_space_idx" ] && [ "$_space_idx" != "?" ] && \
                 [ "$_badge_bind" != "$_space_idx" ] && [ "$_badge_bind" != "missing" ]; then
                _status="STALE"
                echo "│    $_step: ⚠ items bound to space=$_badge_bind but workspace on space=$_space_idx" | tee -a "$ANOMALY_FILE"
            fi

            if [ "$_status" = "ok" ]; then
                printf "│    %-16s  running=%-5s  height=%-4s  items→space=%s\n" \
                    "$_step" "$_running" "$_height" "$_badge_bind"
            fi
        done
        echo "│"
    done
fi

echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# Re-count anomalies (window order + bar health may have added entries)
ANOMALY_COUNT=$(wc -l < "$ANOMALY_FILE" 2>/dev/null | tr -d ' ')

# ──────────────────────────────────────────────────────────────
# 7b. STATE MANIFEST — owned WIDs per workspace
# ──────────────────────────────────────────────────────────────
echo "┌─ State Manifest ─────────────────────────────────────────────────┐"
echo "│"

_STATE_FILE="$REPO_ROOT/state/manifest.json"
if [ -f "$_STATE_FILE" ]; then
    _SM_KEYS=$(jq -r '.workspaces // {} | keys[]' "$_STATE_FILE" 2>/dev/null)
    if [ -n "$_SM_KEYS" ]; then
        for _smk in $_SM_KEYS; do
            _sme=$(jq -r --arg l "$_smk" '.workspaces[$l]' "$_STATE_FILE")
            _sm_sp=$(echo "$_sme" | jq -r '.space_idx // "?"')
            _sm_uuid=$(echo "$_sme" | jq -r '.space_uuid // "?"' | cut -c1-8)
            _sm_papp=$(echo "$_sme" | jq -r '.primary.app // "?"')
            _sm_pwid=$(echo "$_sme" | jq -r '.primary.wid // 0')
            _sm_sapp=$(echo "$_sme" | jq -r '.secondary.app // "?"')
            _sm_swid=$(echo "$_sme" | jq -r '.secondary.wid // 0')
            _sm_mode=$(echo "$_sme" | jq -r '.mode // "?"')

            # Quick liveness: check primary wid
            _sm_live="?"
            if yabai -m query --windows --window "$_sm_pwid" >/dev/null 2>&1; then
                _sm_live="alive"
            else
                _sm_live="stale"
            fi

            if [ "$_sm_mode" = "tile" ] && [ "$_sm_swid" -gt 0 ] 2>/dev/null; then
                printf "│  %-10s space=%-3s uuid=%-8s %s(%s)+%s(%s)  %s\n" \
                    "$_smk" "$_sm_sp" "$_sm_uuid" "$_sm_papp" "$_sm_pwid" "$_sm_sapp" "$_sm_swid" "$_sm_live"
            else
                printf "│  %-10s space=%-3s uuid=%-8s %s(%s)  %s\n" \
                    "$_smk" "$_sm_sp" "$_sm_uuid" "$_sm_papp" "$_sm_pwid" "$_sm_live"
            fi
        done
    else
        echo "│  No workspace entries"
    fi
else
    echo "│  No state manifest (state/manifest.json not found)"
fi
echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 8. SKETCHYBAR CONFIG — live bar + item state
# ──────────────────────────────────────────────────────────────
echo "┌─ Sketchybar Config (live) ──────────────────────────────────────┐"
echo "│"

if pgrep -q sketchybar 2>/dev/null; then
    # Bar-level config
    _BAR_JSON=$(sketchybar --query bar 2>/dev/null)
    if [ -n "$_BAR_JSON" ]; then
        _bar_pos=$(echo "$_BAR_JSON" | jq -r '.position // "?"')
        _bar_h=$(echo "$_BAR_JSON" | jq -r '.height // "?"')
        _bar_color=$(echo "$_BAR_JSON" | jq -r '.color // "?"')
        _bar_display=$(echo "$_BAR_JSON" | jq -r '.display // "?"')
        _bar_drawing=$(echo "$_BAR_JSON" | jq -r '.drawing // "?"')
        printf "│  bar: position=%-8s height=%-4s display=%-6s drawing=%-5s color=%s\n" \
            "$_bar_pos" "$_bar_h" "$_bar_display" "$_bar_drawing" "$_bar_color"
    fi
    echo "│"

    # Space visibility (context for item bindings)
    _VIS_SPACES=$(yabai -m query --spaces 2>/dev/null | jq -r '.[] | select(.["is-visible"] == true) | "s\(.index)=disp\(.display)"' | tr '\n' ' ')
    echo "│  visible spaces: $_VIS_SPACES"
    echo "│"

    # Items per label
    for lbl in $LABELS; do
        [ -z "$lbl" ] && continue
        echo "│  $lbl items:"
        for _suffix in badge label path code term folder close; do
            _item="${lbl}_${_suffix}"
            _item_json=$(sketchybar --query "$_item" 2>/dev/null)
            if [ -n "$_item_json" ] && ! echo "$_item_json" | grep -q "not found"; then
                _drawing=$(echo "$_item_json" | jq -r '.geometry.drawing // "?"')
                _assoc_space=$(echo "$_item_json" | jq -r '.geometry.associated_space_mask // 0')
                _assoc_display=$(echo "$_item_json" | jq -r '.geometry.associated_display // "?"')
                # Convert bitmask to space number
                _space_num="none"
                if [ "$_assoc_space" -gt 0 ] 2>/dev/null; then
                    _b=$_assoc_space _n=0
                    while [ "$_b" -gt 1 ]; do _b=$((_b / 2)); _n=$((_n + 1)); done
                    _space_num="$_n"
                fi
                printf "│    %-16s  drawing=%-5s  space=%-4s  display=%s\n" \
                    "$_item" "$_drawing" "$_space_num" "$_assoc_display"
            else
                printf "│    %-16s  MISSING\n" "$_item"
            fi
        done
        echo "│"
    done
else
    echo "│  sketchybar not running"
fi

echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# ──────────────────────────────────────────────────────────────
# 8b. BAR SANITY — overlaps, unbound items, label contamination
# ──────────────────────────────────────────────────────────────
echo "┌─ Bar Sanity ─────────────────────────────────────────────────────┐"
echo "│"

if pgrep -q sketchybar 2>/dev/null; then
    _OVERLAP_FOUND=0
    _CONTAM_FOUND=0
    _UNBOUND_FOUND=0

    # Collect space bindings per label (from badge items)
    _BIND_LIST=""
    for lbl in $LABELS; do
        [ -z "$lbl" ] && continue
        _bj=$(sketchybar --query "${lbl}_badge" 2>/dev/null)
        if [ -n "$_bj" ] && ! echo "$_bj" | grep -q "not found"; then
            _mask=$(echo "$_bj" | jq -r '.geometry.associated_space_mask // 0' 2>/dev/null)
            _sp="unbound"
            if [ "$_mask" -gt 0 ] 2>/dev/null; then
                _b=$_mask _n=0
                while [ "$_b" -gt 1 ]; do _b=$((_b / 2)); _n=$((_n + 1)); done
                _sp="$_n"
            fi
            _BIND_LIST="${_BIND_LIST}${_sp}|${lbl}\n"

            if [ "$_sp" = "unbound" ]; then
                echo "│  FAIL: ${lbl} items NOT BOUND to any space (visible on ALL spaces)" | tee -a "$ANOMALY_FILE"
                _UNBOUND_FOUND=1
            fi
        fi
    done

    # Check for overlaps: multiple labels bound to same space
    if [ -n "$_BIND_LIST" ]; then
        _DUP_BIND=$(echo -e "$_BIND_LIST" | grep -v '^$' | cut -d'|' -f1 | sort | uniq -d)
        for _dsp in $_DUP_BIND; do
            [ "$_dsp" = "unbound" ] && continue
            _dup_labels=$(echo -e "$_BIND_LIST" | grep "^${_dsp}|" | cut -d'|' -f2 | tr '\n' '+' | sed 's/+$//')
            echo "│  FAIL: Multiple workspaces on space $_dsp → $_dup_labels (items overlap)" | tee -a "$ANOMALY_FILE"
            _OVERLAP_FOUND=1
        done
    fi

    # Check path labels for contamination (log text, unparsed JSON)
    for lbl in $LABELS; do
        [ -z "$lbl" ] && continue
        _pj=$(sketchybar --query "${lbl}_path" 2>/dev/null)
        if [ -n "$_pj" ] && ! echo "$_pj" | grep -q "not found"; then
            _path_label=$(echo "$_pj" | jq -r '.label.value // ""' 2>/dev/null)
            if [ -n "$_path_label" ]; then
                # Check for log text contamination
                if [[ "$_path_label" == *"[bar]"* ]] || [[ "$_path_label" == *"workspace check"* ]] || \
                   [[ "$_path_label" == *"[20"* ]] || [[ "$_path_label" =~ \[[0-9]{2}:[0-9]{2}: ]]; then
                    echo "│  FAIL: ${lbl}_path label CONTAMINATED: '$_path_label'" | tee -a "$ANOMALY_FILE"
                    _CONTAM_FOUND=1
                fi
                # Check for unparsed JSON
                if [[ "$_path_label" == *"{"* ]] || [[ "$_path_label" == *'":'* ]]; then
                    echo "│  FAIL: ${lbl}_path label contains UNPARSED JSON: '$_path_label'" | tee -a "$ANOMALY_FILE"
                    _CONTAM_FOUND=1
                fi
            fi
        fi
    done

    if [ "$_OVERLAP_FOUND" -eq 0 ] && [ "$_CONTAM_FOUND" -eq 0 ] && [ "$_UNBOUND_FOUND" -eq 0 ]; then
        echo "│  ✓ No overlaps, no unbound items, no label contamination"
    fi
else
    echo "│  sketchybar not running — skipped"
fi

echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# Re-count anomalies after bar sanity checks
ANOMALY_COUNT=$(wc -l < "$ANOMALY_FILE" 2>/dev/null | tr -d ' ')

# ──────────────────────────────────────────────────────────────
# 9. SUMMARY
# ──────────────────────────────────────────────────────────────
echo "┌─ Summary ──────────────────────────────────────────────────────┐"
echo "│"
echo "│  Snapshots:  ${#FILES[@]}"
echo "│  Labels:     $(echo $LABELS | tr '\n' ' ')"
echo "│  Anomalies:  ${ANOMALY_COUNT:-0}"
if [ -n "$_DUP_WIDS" ]; then
    echo "│  ⚠ SHARED WIDS: $_DUP_WIDS"
fi

# Show final state: which space each label ended on
for lbl in $LABELS; do
    [ -z "$lbl" ] && continue
    LAST_FILE=""
    for f in "${FILES[@]}"; do
        _l=$(jq -r '.label // ""' "$f")
        [ "$_l" = "$lbl" ] && LAST_FILE="$f"
    done
    [ -z "$LAST_FILE" ] && continue
    _space=$(jq -r '.space_idx // ""' "$LAST_FILE")
    _prim=$(jq -r '.primary_wid // "—"' "$LAST_FILE")
    _sec=$(jq -r '.secondary_wid // "—"' "$LAST_FILE")
    echo "│  $lbl: space=$_space  primary=$_prim  secondary=$_sec"
done
echo "│"
echo "└────────────────────────────────────────────────────────────────┘"
