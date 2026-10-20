#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Installs one or more tools, in the order given. Each tool's own install.sh does the work,
# and each does exactly what its README says, so you can read either.
#   sudo ./install.sh journald cam-heartbeat          install (safe to run again)
#   sudo ./install.sh --uninstall cam-heartbeat       undo
#   ./install.sh --dry-run picam-mjpeg                only print what would be done
#   ./install.sh --list                               the tools that have an installer
set -eu
cd "$(dirname "$0")"

FLAGS=()
TOOLS=()
for arg in "$@"; do
    case "$arg" in
        --list)
            for d in tools/*/; do
                t=$(basename "$d")
                if [ -x "$d/install.sh" ]; then
                    echo "$t"
                else
                    echo "$t  (nothing to install: run it from its folder, see tools/$t/README.md)"
                fi
            done
            exit 0
            ;;
        --uninstall|--dry-run) FLAGS+=("$arg") ;;
        -h|--help)
            sed -n '4,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
        *) TOOLS+=("$arg") ;;
    esac
done

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
