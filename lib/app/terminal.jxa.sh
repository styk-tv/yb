#!/bin/bash
# FILE: lib/app/terminal.jxa.sh
# Engine: JXA (splitview / no yabai)
# Overrides: app_terminal_find, app_terminal_close

# Find Terminal.app window by folder name via System Events.
# Returns "jxa:Terminal:<folder>" or empty.
# $1=work_path $2=space_index (ignored in JXA mode)
app_terminal_find() {
    local work_path="$1"
    local folder
    folder=$(basename "$work_path")
    local found
    found=$(osascript -l JavaScript -e "var fn = '$folder';" -e '
var se = Application("System Events");
var p = se.processes.byName("Terminal");
if (p.exists()) {
    for (var i = 0; i < p.windows.length; i++) {
        if (p.windows[i].title().indexOf(fn) !== -1) { "found"; break; }
    }
}' 2>/dev/null)
    [ "$found" = "found" ] && echo "jxa:Terminal:$folder"
}

# Close Terminal.app window by folder name via System Events.
# $1=work_path
app_terminal_close() {
    local work_path="$1"
    local folder
    folder=$(basename "$work_path")
    osascript -l JavaScript -e "var fn = '$folder';" -e '
var se = Application("System Events");
var p = se.processes.byName("Terminal");
if (p.exists()) {
    for (var i = 0; i < p.windows.length; i++) {
        if (p.windows[i].title().indexOf(fn) !== -1) {
            Application("Terminal").windows[i].close();
            break;
        }
    }
}' 2>/dev/null
}
