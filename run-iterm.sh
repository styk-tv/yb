#!/bin/bash
# FILE: run-iterm.sh — automated iTerm2 launch tester
# Usage: ./run-iterm.sh [method_number]
#   no args = run ALL methods automatically and report results

WORK_PATH="${2:-$HOME/git_ckp/mermaid}"
METHOD=${1:-all}
LOGDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/log"
mkdir -p "$LOGDIR"

check_window() {
    sleep 3
    local count
    count=$(osascript -e 'tell application "iTerm2" to get count of windows' 2>/dev/null)
    echo "$count"
}

kill_iterm_windows() {
    osascript -e 'tell application "iTerm2" to close every window' 2>/dev/null
    sleep 1
}

run_method() {
    local num=$1
    local label=$2
    local script=$3

    echo "--- Method $num: $label ---"
    kill_iterm_windows

    local result
    result=$(osascript 2>&1 -e "$script")
    local exit_code=$?
    local wcount
    wcount=$(check_window)

    local status="FAIL"
    [ "$wcount" -gt 0 ] 2>/dev/null && status="OK"

    echo "  AppleScript exit: $exit_code"
    echo "  Output: $result"
    echo "  Windows alive after 3s: $wcount"
    echo "  Result: $status"
    echo ""
    echo "$num|$label|$exit_code|$wcount|$status" >> "$LOGDIR/results.log"
}

# Clear previous results
> "$LOGDIR/results.log"

echo "=== iTerm2 Launch Tester ==="
echo "Target dir: $WORK_PATH"
echo "Logging to: $LOGDIR/results.log"
echo ""

# Method 1: default profile, no command
run_method 1 "default profile (login shell)" '
tell application "iTerm2"
    activate
    delay 0.5
    create window with default profile
end tell
'

# Method 2: default profile + /bin/bash -l
run_method 2 "default profile + /bin/bash -l" '
tell application "iTerm2"
    activate
    delay 0.5
    create window with default profile command "/bin/bash -l"
end tell
'

# Method 3: profile "Peter"
run_method 3 "profile Peter" '
tell application "iTerm2"
    activate
    delay 0.5
    create window with profile "Peter"
end tell
'

# Method 4: Cmd+N keystroke
run_method 4 "Cmd+N keystroke" '
tell application "iTerm2" to activate
delay 0.5
tell application "System Events"
    tell process "iTerm2"
        keystroke "n" using command down
    end tell
end tell
'

# Method 5: Shell > New Window menu
run_method 5 "Shell > New Window menu" '
tell application "iTerm2" to activate
delay 0.5
tell application "System Events"
    tell process "iTerm2"
        click menu item "New Window" of menu 1 of menu bar item "Shell" of menu bar 1
    end tell
end tell
'

# Method 6: /usr/bin/top (non-bash, guaranteed interactive)
run_method 6 "default profile + /usr/bin/top" '
tell application "iTerm2"
    activate
    delay 0.5
    create window with default profile command "/usr/bin/top"
end tell
'

# Method 7: /bin/cat (stays alive waiting for stdin)
run_method 7 "default profile + /bin/cat" '
tell application "iTerm2"
    activate
    delay 0.5
    create window with default profile command "/bin/cat"
end tell
'

# Method 8: Terminal.app baseline
echo "--- Method 8: Terminal.app baseline ---"
kill_iterm_windows
osascript -e 'tell application "Terminal" to do script "echo TERMINAL_OK"' 2>&1
osascript -e 'tell application "Terminal" to activate' 2>&1
sleep 3
local_tc=$(osascript -e 'tell application "Terminal" to get count of windows' 2>/dev/null)
t_status="FAIL"
[ "$local_tc" -gt 0 ] 2>/dev/null && t_status="OK"
echo "  Windows alive after 3s: $local_tc"
echo "  Result: $t_status"
echo "8|Terminal.app baseline|0|$local_tc|$t_status" >> "$LOGDIR/results.log"
# Close Terminal test window
osascript -e 'tell application "Terminal" to close every window' 2>/dev/null
echo ""

# Summary
echo "=== RESULTS ==="
echo ""
printf "%-4s %-36s %-6s %-8s %s\n" "#" "Method" "Exit" "Windows" "Status"
echo "---- ------------------------------------ ------ -------- ------"
while IFS='|' read -r num label ec wc st; do
    printf "%-4s %-36s %-6s %-8s %s\n" "$num" "$label" "$ec" "$wc" "$st"
done < "$LOGDIR/results.log"
echo ""
echo "Log saved to: $LOGDIR/results.log"

# Cleanup
kill_iterm_windows
