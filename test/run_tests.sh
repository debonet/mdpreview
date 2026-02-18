#!/usr/bin/env bash

S_DIR_TEST="$(cd "$(dirname "$0")" && pwd)"
S_DIR_PROJECT="$(cd "$S_DIR_TEST/.." && pwd)"
S_DIR_FIXTURES="$S_DIR_TEST/fixtures"
S_DIR_STUBS="$S_DIR_TEST/stubs"
S_MDPREVIEW="$S_DIR_PROJECT/mdpreview"

S_DIR_TMP="$(mktemp -d)"
S_DIR_FAKE_HOME="$S_DIR_TMP/fakehome"
S_DIR_FAKE_USER="$S_DIR_FAKE_HOME/.mdpreview"
mkdir -p "$S_DIR_FAKE_USER"

cPass=0
cFail=0
cTotal=0

f_cleanup() {
    rm -rf "$S_DIR_TMP"
}
trap f_cleanup EXIT

f_pass() {
    cPass=$((cPass + 1))
    cTotal=$((cTotal + 1))
    printf "PASS: %s\n" "$1"
}

f_fail() {
    cFail=$((cFail + 1))
    cTotal=$((cTotal + 1))
    printf "FAIL: %s — %s\n" "$1" "$2"
}

f_assert_contains() {
    if [[ "$1" == *"$2"* ]]; then
        f_pass "$3"
    else
        f_fail "$3" "expected to contain '$2'"
    fi
}

f_assert_not_contains() {
    if [[ "$1" != *"$2"* ]]; then
        f_pass "$3"
    else
        f_fail "$3" "expected NOT to contain '$2'"
    fi
}

f_assert_nonempty() {
    if [[ -n "$1" ]]; then
        f_pass "$2"
    else
        f_fail "$2" "expected non-empty output"
    fi
}

f_assert_exit_code() {
    if [[ "$1" -eq "$2" ]]; then
        f_pass "$3"
    else
        f_fail "$3" "expected exit $2, got $1"
    fi
}

f_run() {
    HOME="$S_DIR_FAKE_HOME" \
    PATH="$S_DIR_STUBS:$PATH" \
    "$S_MDPREVIEW" "$@" 2>&1
}

fz_exit() {
    HOME="$S_DIR_FAKE_HOME" \
    PATH="$S_DIR_STUBS:$PATH" \
    "$S_MDPREVIEW" "$@" >/dev/null 2>&1
    echo $?
}

fs_html() {
    local s_path="/tmp/preview-sample.html"
    rm -f "$s_path"
    f_run "$@" "$S_DIR_FIXTURES/sample.md" >/dev/null 2>&1
    [[ -f "$s_path" ]] && cat "$s_path"
}


printf "=== mdpreview test suite ===\n\n"
printf "%s\n" "--- Style Resolution Precedence ---"

s_html="$(fs_html)"
f_assert_contains "$s_html" "Arial" "default (no flags, no env, no default.css) uses gdocs CSS"

s_html="$(fs_html --style github)"
f_assert_contains "$s_html" "BlinkMacSystemFont" "flag --style github uses github CSS"

s_html="$(fs_html --style=dark)"
f_assert_contains "$s_html" "#0d1117" "flag --style=dark uses dark CSS (equals syntax)"

s_html="$(
    rm -f /tmp/preview-sample.html
    HOME="$S_DIR_FAKE_HOME" \
    PATH="$S_DIR_STUBS:$PATH" \
    MDPREVIEW_STYLE=academic \
    "$S_MDPREVIEW" "$S_DIR_FIXTURES/sample.md" >/dev/null 2>&1
    cat /tmp/preview-sample.html 2>/dev/null
)"
f_assert_contains "$s_html" "Georgia" "env MDPREVIEW_STYLE=academic uses academic CSS"

s_html="$(
    rm -f /tmp/preview-sample.html
    HOME="$S_DIR_FAKE_HOME" \
    PATH="$S_DIR_STUBS:$PATH" \
    MDPREVIEW_STYLE=academic \
    "$S_MDPREVIEW" --style github "$S_DIR_FIXTURES/sample.md" >/dev/null 2>&1
    cat /tmp/preview-sample.html 2>/dev/null
)"
f_assert_contains "$s_html" "BlinkMacSystemFont" "flag --style overrides MDPREVIEW_STYLE env var"
f_assert_not_contains "$s_html" "Georgia" "flag --style overrides MDPREVIEW_STYLE (no academic)"

cp "$S_DIR_FIXTURES/custom.css" "$S_DIR_FAKE_USER/default.css"
s_html="$(fs_html)"
f_assert_contains "$s_html" "Comic Sans MS" "~/.mdpreview/default.css used when no flag or env set"
rm -f "$S_DIR_FAKE_USER/default.css"

s_html="$(fs_html --style "$S_DIR_FIXTURES/custom.css")"
f_assert_contains "$s_html" "Comic Sans MS" "flag --style /path/to/file.css reads custom CSS file"


printf "\n%s\n" "--- Built-in Styles ---"

vs_builtin=("gdocs" "github" "dark" "academic")
vs_selector=("body" "h1" "pre" "code")
for s_name in "${vs_builtin[@]}"; do
    s_html="$(fs_html --style "$s_name")"
    f_assert_nonempty "$s_html" "built-in '$s_name' produces non-empty HTML"
    for s_sel in "${vs_selector[@]}"; do
        f_assert_contains "$s_html" "$s_sel" "built-in '$s_name' contains '$s_sel' selector"
    done
done

s_html="$(fs_html --style gdocs)"
f_assert_contains "$s_html" "Arial" "gdocs uses Arial"

s_html="$(fs_html --style github)"
f_assert_contains "$s_html" "-apple-system" "github uses system font stack"

s_html="$(fs_html --style dark)"
f_assert_contains "$s_html" "#0d1117" "dark has #0d1117 background"

s_html="$(fs_html --style academic)"
f_assert_contains "$s_html" "Georgia" "academic uses Georgia"


printf "\n%s\n" "--- Style Name Resolution ---"

cp "$S_DIR_FIXTURES/custom.css" "$S_DIR_FAKE_USER/github.css"
s_html="$(fs_html --style github)"
f_assert_contains "$s_html" "Comic Sans MS" "user override in ~/.mdpreview/name.css takes precedence"
rm -f "$S_DIR_FAKE_USER/github.css"

s_html="$(fs_html --style github)"
f_assert_contains "$s_html" "BlinkMacSystemFont" "falls back to built-in when no user override"

s_out="$(f_run --style nonexistent "$S_DIR_FIXTURES/sample.md")"
z_exit=$(fz_exit --style nonexistent "$S_DIR_FIXTURES/sample.md")
f_assert_contains "$s_out" "Error" "unknown style name produces error message"
f_assert_exit_code "$z_exit" 1 "unknown style name exits with code 1"


printf "\n%s\n" "--- @import Support ---"

cp "$S_DIR_FIXTURES/importer.css" "$S_DIR_FAKE_USER/importer.css"
cp "$S_DIR_FIXTURES/imported.css" "$S_DIR_FAKE_USER/imported.css"
s_html="$(fs_html --style importer)"
f_assert_contains "$s_html" "color: #090" "@import inlines imported content"
f_assert_contains "$s_html" "Verdana" "@import preserves importing file content"
rm -f "$S_DIR_FAKE_USER/importer.css" "$S_DIR_FAKE_USER/imported.css"

cp "$S_DIR_FIXTURES/cycle_a.css" "$S_DIR_FAKE_USER/cycle_a.css"
cp "$S_DIR_FIXTURES/cycle_b.css" "$S_DIR_FAKE_USER/cycle_b.css"
rm -f /tmp/preview-sample.html
f_run --style cycle_a "$S_DIR_FIXTURES/sample.md" >/dev/null 2>&1 &
z_pid=$!
( sleep 10 && kill "$z_pid" 2>/dev/null ) &
z_pid_watchdog=$!
wait "$z_pid" 2>/dev/null
z_cycle_exit=$?
kill "$z_pid_watchdog" 2>/dev/null
wait "$z_pid_watchdog" 2>/dev/null
if [[ "$z_cycle_exit" -ne 137 ]]; then
    f_pass "cycle detection does not hang (no infinite loop)"
else
    f_fail "cycle detection does not hang (no infinite loop)" "process was killed by watchdog"
fi
s_html_cycle=""
[[ -f /tmp/preview-sample.html ]] && s_html_cycle="$(cat /tmp/preview-sample.html)"
f_assert_contains "$s_html_cycle" "color: red" "cycle A content is present"
f_assert_contains "$s_html_cycle" "color: blue" "cycle B content is present (imported once)"
rm -f "$S_DIR_FAKE_USER/cycle_a.css" "$S_DIR_FAKE_USER/cycle_b.css"

cp "$S_DIR_FIXTURES/imports_builtin.css" "$S_DIR_FAKE_USER/imports_builtin.css"
s_html="$(fs_html --style imports_builtin)"
f_assert_contains "$s_html" "BlinkMacSystemFont" "@import of built-in name resolves correctly"
f_assert_contains "$s_html" "color: red" "@import of built-in preserves local rules"
rm -f "$S_DIR_FAKE_USER/imports_builtin.css"


printf "\n%s\n" "--- --list-styles ---"

s_out="$(f_run --list-styles)"
for s_name in "${vs_builtin[@]}"; do
    f_assert_contains "$s_out" "$s_name" "--list-styles shows built-in '$s_name'"
done
f_assert_contains "$s_out" "[default]" "--list-styles marks the default"

cp "$S_DIR_FIXTURES/custom.css" "$S_DIR_FAKE_USER/mytheme.css"
s_out="$(f_run --list-styles)"
f_assert_contains "$s_out" "mytheme" "--list-styles shows user styles from ~/.mdpreview/"
rm -f "$S_DIR_FAKE_USER/mytheme.css"

z_exit=$(fz_exit --list-styles)
f_assert_exit_code "$z_exit" 0 "--list-styles works without a file argument"


printf "\n%s\n" "--- HTML Output ---"

s_html="$(fs_html --style gdocs)"
f_assert_contains "$s_html" "Arial" "HTML output contains the correct style CSS"
f_assert_contains "$s_html" "<title>mdpreview</title>" "HTML title is set to mdpreview"
f_assert_contains "$s_html" "mermaid" "HTML output contains mermaid script"


printf "\n%s\n" "--- Error Cases ---"

s_out="$(f_run --style nonexistent "$S_DIR_FIXTURES/sample.md")"
z_exit=$(fz_exit --style nonexistent "$S_DIR_FIXTURES/sample.md")
f_assert_exit_code "$z_exit" 1 "--style nonexistent exits with error"

s_out="$(f_run --style /nonexistent/path.css "$S_DIR_FIXTURES/sample.md")"
z_exit=$(fz_exit --style /nonexistent/path.css "$S_DIR_FIXTURES/sample.md")
f_assert_contains "$s_out" "Error" "--style /nonexistent/path.css produces error"
f_assert_exit_code "$z_exit" 1 "--style /nonexistent/path.css exits with error"

s_out="$(f_run 2>&1)"
z_exit=$(fz_exit)
f_assert_contains "$s_out" "Usage" "no file argument shows usage message"
f_assert_exit_code "$z_exit" 1 "no file argument exits with error"


printf "\n=== Results ===\n"
printf "Passed: %d / %d\n" "$cPass" "$cTotal"
printf "Failed: %d / %d\n" "$cFail" "$cTotal"

[[ "$cFail" -eq 0 ]] && exit 0 || exit 1
