#!/bin/bash
# FILE: lib/app/iterm.jxa.sh
# Engine: JXA (splitview / no yabai)
# Overrides: app_iterm_find, app_iterm_close

# Find iTerm2 window by session.path via AppleScript.
# Returns "jxa:iTerm2:<id>" or empty.
# $1=work_path $2=space_index (ignored in JXA mode)
app_iterm_find() {
    local work_path="$1"
    local as_id
    as_id=$(osascript \
        -e "set targetPath to \"$work_path\"" \
        -e 'tell application "iTerm"' \
        -e '    repeat with w in windows' \
        -e '        try' \
        -e '            tell current session of w' \
        -e '                set p to (variable named "session.path")' \
        -e '                if p ends with "/" then set p to text 1 thru -2 of p' \
        -e '                if p is equal to targetPath then' \
        -e '                    return id of w' \
        -e '                end if' \
        -e '            end tell' \
        -e '        end try' \
        -e '    end repeat' \
        -e '    return ""' \
        -e 'end tell' 2>/dev/null)
    [ -n "$as_id" ] && echo "jxa:iTerm2:$as_id"
}

# Close iTerm2 window by session.path via AppleScript.
# $1=work_path
app_iterm_close() {
    local work_path="$1"
    osascript \
        -e "set targetPath to \"$work_path\"" \
        -e 'tell application "iTerm"' \
        -e '    repeat with w in windows' \
        -e '        try' \
        -e '            tell current session of w' \
        -e '                set p to (variable named "session.path")' \
        -e '                if p ends with "/" then set p to text 1 thru -2 of p' \
        -e '                if p is equal to targetPath then' \
        -e '                    close w' \
        -e '                    exit repeat' \
        -e '                end if' \
        -e '            end tell' \
        -e '        end try' \
        -e '    end repeat' \
        -e 'end tell' 2>/dev/null
}
