#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Refuse to publish private identifiers. Scans the repo's text files (or the files given)
# for generic patterns (private IPs, MAC addresses, email addresses, Telegram tokens,
# passwords piped into sudo, private keys) and for every string in a PRIVATE denylist
# kept outside the repo: $TOOLKIT_DENYLIST, or ~/.config/motioneye-pi-toolkit/denylist.txt
# (one fixed string per line, case-insensitive, '#' starts a comment). Never commit it.
# Exit 0 = clean, 1 = hits (printed as file:line, so run it only on your own machine),
# 2 = the check itself failed (treat as NOT clean).
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
DENY=${TOOLKIT_DENYLIST:-$HOME/.config/motioneye-pi-toolkit/denylist.txt}

if [ $# -gt 0 ]; then
    FILES=("$@")
else
    mapfile -t FILES < <(find . -type f -not -path './.git/*' | sed 's#^\./##' | sort)
fi
TEXT=()
for f in "${FILES[@]}"; do
    if [ -f "$f" ] && grep -Iq . "$f"; then TEXT+=("$f"); fi
done
if [ ${#TEXT[@]} -eq 0 ]; then echo "scrub-check: no text files"; exit 0; fi

HITS=0
fail() {
    echo "scrub-check: ERROR $1 - result is NOT clean"
    exit 2
}
check() {  # label, grep -E pattern, files...
    local label=$1 pat=$2 out rc
    shift 2
    out=$(grep -nHiE -- "$pat" "$@")
    rc=$?
    if [ $rc -gt 1 ]; then fail "grep failed for '$label' (rc=$rc)"; fi
    out=$(printf '%s\n' "$out" | grep -viE '@(example\.(com|org|net)|users\.noreply\.github\.com)' | grep -v '^$')
    if [ -n "$out" ]; then
        echo "== $label"
        echo "$out" | cut -c1-200
        HITS=1
    fi
}
# this script contains the patterns themselves, so it is skipped for the generic checks
GEN=()
for f in "${TEXT[@]}"; do
    if [ "$f" != scripts/scrub-check.sh ]; then GEN+=("$f"); fi
done
if [ ${#GEN[@]} -gt 0 ]; then
    check "private IPv4 address" '\b(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b' "${GEN[@]}"
    check "MAC address" '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b' "${GEN[@]}"
    check "email address" '[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}' "${GEN[@]}"
    check "Telegram bot token" '\b[0-9]{8,10}:[a-z0-9_-]{30,}\b' "${GEN[@]}"
    check "password piped into sudo" 'sudo +-S' "${GEN[@]}"
    check "private key" 'BEGIN [A-Z ]*PRIVATE KEY' "${GEN[@]}"
fi

# denylist: lowercase both sides and match fixed strings without -i
# (grep -iF crashes in some Git for Windows builds)
if [ -f "$DENY" ]; then
    PF=$(mktemp) || fail "mktemp failed"
    grep -v '^[[:space:]]*#' "$DENY" | grep -v '^[[:space:]]*$' | tr '[:upper:]' '[:lower:]' > "$PF"
    if [ -s "$PF" ]; then
        out=
        for f in "${TEXT[@]}"; do
            o=$(tr '[:upper:]' '[:lower:]' < "$f" | grep -nF -f "$PF")
            rc=$?
            if [ $rc -gt 1 ]; then rm -f "$PF"; fail "denylist grep failed on $f (rc=$rc)"; fi
            if [ -n "$o" ]; then out+=$(printf '%s\n' "$o" | sed "s|^|$f:|")$'\n'; fi
        done
        rm -f "$PF"
        if [ -n "$out" ]; then
            echo "== private denylist"
            printf '%s' "$out" | cut -c1-200
            HITS=1
        fi
    else
        rm -f "$PF"
        echo "scrub-check: WARNING the denylist at $DENY has no entries"
    fi
else
    echo "scrub-check: WARNING no private denylist at $DENY (generic checks only)"
fi

if [ $HITS -eq 0 ]; then echo "scrub-check: clean (${#TEXT[@]} files)"; fi
exit $HITS
