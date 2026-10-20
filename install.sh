#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Installs one or more tools, in the order given. Each tool's own install.sh does the work,
# and each does exactly what its README says, so you can read either.
#   sudo ./install.sh journald cam-heartbeat          install (safe to run again)
#   sudo ./install.sh --uninstall cam-heartbeat       undo
#   ./install.sh --dry-run picam-mjpeg                only print what would be done
#   ./install.sh --list                               the tools that have an installer
# On a Pi that has no copy of the toolkit yet, download just this script and run it; it fetches
# the rest of the toolkit into a temporary folder by itself:
#   wget https://raw.githubusercontent.com/free-cup-holder-exe/motioneye-pi-toolkit/main/install.sh
#   sudo bash install.sh journald cam-heartbeat
set -eu
cd "$(dirname "$0")"

TARBALL=https://github.com/free-cup-holder-exe/motioneye-pi-toolkit/archive/refs/heads/main.tar.gz
FLAGS=()
TOOLS=()
LIST=
for arg in "$@"; do
    case "$arg" in
        --list) LIST=1 ;;
        --uninstall|--dry-run) FLAGS+=("$arg") ;;
        -h|--help)
            sed -n '4,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
        *) TOOLS+=("$arg") ;;
    esac
done

if [ ! -d tools ]; then
    echo "no toolkit folder next to this script: fetching the toolkit from GitHub"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$TARBALL" -o "$TMP/toolkit.tar.gz"
    else
        wget -q -O "$TMP/toolkit.tar.gz" "$TARBALL"
    fi
    tar -xzf "$TMP/toolkit.tar.gz" -C "$TMP" --strip-components=1
    cd "$TMP"
    echo "fetched; the by-hand steps are in each tool's README.md on GitHub"
fi

if [ -n "$LIST" ]; then
    for d in tools/*/; do
        t=$(basename "$d")
        if [ -x "$d/install.sh" ]; then
            echo "$t"
        else
            echo "$t  (nothing to install: run it from its folder, see tools/$t/README.md)"
        fi
    done
    exit 0
fi

if [ ${#TOOLS[@]} -eq 0 ]; then
    echo "which tool? ./install.sh --list shows them; e.g. sudo ./install.sh journald cam-heartbeat" >&2
    exit 2
fi

for t in "${TOOLS[@]}"; do
    if [ ! -d "tools/$t" ]; then
        echo "no such tool: $t (./install.sh --list)" >&2
        exit 2
    fi
    if [ ! -x "tools/$t/install.sh" ]; then
        echo "[$t] nothing to install: run it from tools/$t, see tools/$t/README.md"
        continue
    fi
    echo "===== $t"
    (cd "tools/$t" && TOOL=$t ./install.sh "${FLAGS[@]+"${FLAGS[@]}"}")
done
