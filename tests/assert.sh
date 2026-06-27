#!/usr/bin/env bash
# Minimal assertion helpers for Shadow Legion shell tests.
ASSERT_FAILS=0
_pass(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
_fail(){ printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; ASSERT_FAILS=$((ASSERT_FAILS+1)); }
assert_eq(){       [ "$1" = "$2" ] && _pass "${3:-eq}" || _fail "${3:-eq: expected [$1] got [$2]"; }
assert_contains(){ case "$1" in *"$2"*) _pass "${3:-contains}";; *) _fail "${3:-contains: [$1] missing [$2]";; esac; }
assert_exit(){     [ "$1" -eq "$2" ] && _pass "${3:-exit}" || _fail "${3:-exit: expected exit $1 got $2"; }
assert_done(){ [ "$ASSERT_FAILS" -eq 0 ] || { printf '%d assertion(s) failed\n' "$ASSERT_FAILS" >&2; exit 1; }; }
