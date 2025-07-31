#!/bin/bash

set -euo pipefail

PACKAGE_FILE="$1"

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

read -rp "Do you want to remove the installed packages? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo pacman -Rns "${installed[@]}"
    
    echo "Checking for orphaned packages..."
    orphans=$(pacman -Qtdq) || true
    if [[ -n "$orphans" ]]; then
        echo "Orphaned packages detected:"
        echo "$orphans"
        read -rp "Remove all orphaned packages? [y/N] " confirm_orphans
        if [[ "$confirm_orphans" =~ ^[Yy]$ ]]; then
            sudo pacman -Rns $orphans
        else
            echo "Skipping orphan removal."
        fi
    else
        echo "No orphaned packages found."
    fi
else
    echo "Aborted. No packages were removed."
fi
