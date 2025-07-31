#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <package-list-file> [--dry-run]"
    exit 1
fi

PACKAGE_FILE="$1"

# Global flag
DRY_RUN=false

# Optional second argument --dry-run
if [[ "${2:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "Package list file not found: $PACKAGE_FILE"
    exit 1
fi

installed=()
not_installed=()

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue  # skip empty or commented lines
    if pacman -Q "$pkg" &>/dev/null; then
        installed+=("$pkg")
    else
        not_installed+=("$pkg")
    fi
done < "$PACKAGE_FILE"

echo "====== Package Check Summary ======"
echo "Installed packages:"
printf '  - %s\n' "${installed[@]}"
echo
echo "Not installed packages:"
printf '  - %s\n' "${not_installed[@]}"
echo "==================================="

if [[ ${#installed[@]} -eq 0 ]]; then
    echo "No installed packages to remove."
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Simulating removal of packages: ${installed[*]}"
else
    read -rp "Do you want to remove the installed packages? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo pacman -Rns "${installed[@]}"
    else
        echo "Aborted. No packages were removed."
    fi
fi

echo "Checking for orphaned packages..."
orphans=$(pacman -Qtdq) || true
if [[ -n "$orphans" ]]; then
    echo "Orphaned packages detected:"
    echo "$orphans"
    echo
    read -rp "Remove all orphaned packages? [y/N] " confirm_orphans
    if [[ "$confirm_orphans" =~ ^[Yy]$ ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Simulating removal of orphans."
        else
            sudo pacman -Rns $orphans
        fi
    else
        echo "Skipping orphan removal."
    fi
else
    echo "No orphaned packages found."
fi