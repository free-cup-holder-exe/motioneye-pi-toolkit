#!/bin/bash
# Install a pre-commit hook that runs scripts/scrub-check.sh on the files being committed.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK=$ROOT/.git/hooks/pre-commit
if [ ! -d "$ROOT/.git/hooks" ]; then echo "not a git checkout: $ROOT"; exit 1; fi
cat > "$HOOK" <<'EOF'
#!/bin/bash
# runs the working-tree copy of each staged file through the scrub check
mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR)
if [ ${#files[@]} -eq 0 ]; then exit 0; fi
exec "$(git rev-parse --show-toplevel)/scripts/scrub-check.sh" "${files[@]}"
EOF
chmod +x "$HOOK"
echo "installed $HOOK"
