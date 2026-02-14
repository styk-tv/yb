# YB Runner Specification

A runner is a standalone bash script that does one thing for a workspace. Think of it like a Kubernetes Job &mdash; YB submits it with arguments, waits for it to exit, and reads its stdout. Runners don't know about each other. YB is the controller that sequences them.

---

## Mental model

```
                    ┌──────────────────────────┐
  instance.yaml ──→ │         yb.sh            │
                    │  (controller / sequencer) │
                    └────┬────────┬────────┬───┘
                         │        │        │
                    space.sh  <runner>  bar.sh
                    (step 1)  (step 2)  (step 3)
```

Your runner is **step 2**. By the time it runs, a virtual desktop already exists on the target display. When it exits, YB will configure the status bar and apply zoom. Your only job: **open and position windows**.

On a workspace **switch** (already open), YB skips step 1 and calls `tile.sh` instead of your runner to reposition existing windows, then updates the bar.

---

## Contract

| Rule | Detail |
|---|---|
| Location | `runners/<name>.sh` |
| Shell | `#!/bin/bash` &mdash; macOS bash 3.2 (no associative arrays, no `\u` escapes) |
| Executable | `chmod +x` |
| Line 3 | `# Description here` &mdash; YB extracts this for `yb` status output |
| Exit | `0` success, `1` failure |
| Side effects | Open apps, move/resize windows on the target display. Nothing else. |
| Isolation | Must not call other runners. May call system tools, osascript, python3, CLIs. |

---

## Header

```bash
#!/bin/bash
# FILE: runners/myrunner.sh
# One-line description shown in yb status output
#
# Usage:
#   ./runners/myrunner.sh --display 3 --path ~/project
```

**Line 3 is read by YB.** Everything else in the header is for humans.

---

## Arguments

YB passes `--key value` pairs. Accept what you need, reject what you don't.

```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) DISPLAY_ID="$2"; shift 2 ;;
        --path)    WORK_PATH="$2"; shift 2 ;;
        --cmd)     CMD="$2"; shift 2 ;;
        --gap)     GAP="$2"; shift 2 ;;
        --pad)     IFS=',' read -r PAD_T PAD_B PAD_L PAD_R <<< "$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done
```

### What YB passes

| Argument | From YAML | Passed when | What it means |
|---|---|---|---|
| `--display` | `display` | Always | Target display ID (integer, stable across reboots) |
| `--path` | `path` | Always | Workspace folder. May contain `~` &mdash; expand it yourself |
| `--cmd` | `cmd` | Non-null, non-empty | Command to run in terminal after `cd` |
| `--gap` | `gap` | Non-zero | Pixel gap between windows |
| `--pad` | `padding` | Not `0,0,0,0` | Edge insets as `top,bottom,left,right` |

**Tilde expansion** (do this early):
```bash
WORK_PATH=$(echo "$WORK_PATH" | sed "s|~|$HOME|")
```

You can define extra arguments (e.g. `--app`, `--proc`) for direct CLI use. YB won't pass them.

---

## Output

Print progress lines for the user:

```
[tag]   message
```

Tag is 4-6 chars in brackets, then 2-3 spaces, then message. YB displays stdout verbatim. No special parsing &mdash; purely cosmetic.

```
[open]  Visual Studio Code → ~/project
[wait]  polling for Code window (folder=mermaid)...
[tile]  Code [mermaid] 726,-1440 1720x1440
[done]  split ready
```

---

## Registration

1. Drop your script in `runners/`
2. `chmod +x runners/myrunner.sh`
3. Reference it from an instance:

```yaml
# instances/example.yaml
runner: myrunner
path: ~/projects/example
display: 3
bar: standard
gap: 0
padding: 0,0,0,0
zoom: 0
cmd: null
```

YB resolves `runner: myrunner` to `runners/myrunner.sh`. No other registration, no config files, no imports.

---

## Example: kubectl runner

A runner that doesn't position windows at all &mdash; it submits a Kubernetes Job and waits for completion by polling resource status.

```bash
#!/bin/bash
# FILE: runners/kjob.sh
# Submit a Kubernetes Job and wait for completion
#
# Usage:
#   ./runners/kjob.sh --display 3 --path ~/k8s/jobs --cmd "process-data"

DISPLAY_ID=""
WORK_PATH=""
CMD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --display) DISPLAY_ID="$2"; shift 2 ;;
        --path)    WORK_PATH="$2"; shift 2 ;;
        --cmd)     CMD="$2"; shift 2 ;;
        *)         echo "Unknown: $1"; exit 1 ;;
    esac
done

WORK_PATH=$(echo "$WORK_PATH" | sed "s|~|$HOME|")
JOB_NAME="yb-${CMD:-default}-$(date +%s)"

if [ -z "$DISPLAY_ID" ] || [ -z "$WORK_PATH" ]; then
    echo "Usage: kjob.sh --display <id> --path <workspace> --cmd <job-template>"
    exit 1
fi

echo "[kjob]  submitting $JOB_NAME from $WORK_PATH"

# Submit the job
kubectl apply -f "$WORK_PATH/$CMD.yaml" 2>&1 | while read -r line; do
    echo "[kjob]  $line"
done

# Poll for completion — not the API ack, the actual resource status
echo "[wait]  polling for job completion..."
for i in $(seq 1 60); do
    STATUS=$(kubectl get job "$JOB_NAME" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
    if [ "$STATUS" = "Complete" ]; then
        echo "[done]  job $JOB_NAME completed (${i}s)"
        exit 0
    elif [ "$STATUS" = "Failed" ]; then
        echo "[fail]  job $JOB_NAME failed (${i}s)"
        exit 1
    fi
    sleep 1
done

echo "[fail]  job $JOB_NAME timed out after 60s"
exit 1
```

This runner doesn't touch windows or displays &mdash; it uses YB purely as a task orchestrator. The `--display` and `--path` arguments give it context about *where* and *what*, but it's free to ignore what it doesn't need.

---

## Example: window runner

A runner that opens a single app on a display. See `runners/solo.sh` for the full implementation. The key pattern:

1. Open the app (`open -na "AppName" --args "$WORK_PATH"`)
2. Poll until a window exists
3. Position the window using System Events via osascript

Existing runners (`split.sh`, `solo.sh`, `tile.sh`) all use JXA with `ObjC.import("AppKit")` to resolve the display ID to screen coordinates and `System Events` to move windows. Read any of them as a starting point &mdash; the pattern is the same.

---

## Existing runners

| Runner | Purpose | Arguments |
|---|---|---|
| `split` | VS Code + Terminal side-by-side | `--display --path [--cmd --gap --pad]` |
| `tile` | Reposition existing windows | `--display --path [--gap --pad]` |
| `solo` | Single app fullscreen | `--display --path [--app --proc --pad]` |
| `space` | Create/list virtual desktops | `--create --display` or `--list` |
| `bar` | SketchyBar configuration | `--style --display [--label --path]` |

---

## Constraints

**Bash 3.2** (macOS default) &mdash; these are unavailable:

| Missing | Use instead |
|---|---|
| `\u` escapes | `python3 -c "print('\ue7a8',end='')"` |
| `declare -A` | Positional args or `IFS` parsing |
| `mapfile` | `while read` loop |
| `&>>` | `>> file 2>&1` |
