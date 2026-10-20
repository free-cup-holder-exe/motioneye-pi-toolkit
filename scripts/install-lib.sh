#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Shared by every tools/*/install.sh. Sourced, not run.
#   MODE=install|uninstall, DRY=1 prints the commands instead of running them.
#   run <cmd...>   prints the command, then runs it unless DRY=1
#   say <text>     prints a line prefixed with the tool name

TOOL=${TOOL:-$(basename "$(pwd)")}
MODE=install
DRY=

for arg in "$@"; do
    case "$arg" in
        --uninstall) MODE=uninstall ;;
        --dry-run) DRY=1 ;;
        -h|--help)
            echo "usage: sudo ./install.sh [--uninstall] [--dry-run]"
            exit 0
            ;;
        *)
            echo "unknown option: $arg (use --uninstall or --dry-run)" >&2
            exit 2
            ;;
    esac
done

if [ -z "$DRY" ] && [ "$(id -u)" != 0 ]; then
    echo "run with sudo (sudo ./install.sh ... from this folder, or sudo ./install.sh $TOOL from the toolkit folder)" >&2
    exit 1
fi

say() {
    echo "[$TOOL] $*"
}

run() {
    echo "+ $*"
    if [ -z "$DRY" ]; then
        "$@"
    fi
}

# crontab helpers for root's crontab: add a line once, or remove every line containing a string
cron_add() {
    if crontab -l 2>/dev/null | grep -qF -- "$1"; then
        say "crontab already has: $1"
        return
    fi
    echo "+ crontab: add '$1'"
    if [ -z "$DRY" ]; then
        (crontab -l 2>/dev/null; echo "$1") | crontab -
    fi
}

cron_remove() {
    if ! crontab -l 2>/dev/null | grep -qF -- "$1"; then
        return
    fi
    echo "+ crontab: remove lines containing '$1'"
    if [ -z "$DRY" ]; then
        crontab -l 2>/dev/null | grep -vF -- "$1" | crontab -
    fi
}

# remove files that exist, quietly skip the rest
remove_files() {
    for f in "$@"; do
        if [ -e "$f" ]; then
            run rm -f "$f"
        fi
    done
}
