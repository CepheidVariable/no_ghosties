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

# Declare global variable for hook usage
initial_orphans=""
new_orphans=()

################################################
# HOOK: Capture pre-removal orphan list
################################################
pre_removal_hook() {
    initial_orphans=$(pacman -Qtdq 2>/dev/null || true)
}

################################################
# HOOK: Determine new orphans and optionally remove
################################################
post_removal_hook() {
    final_orphans=$(pacman -Qtdq 2>/dev/null || true)

    # Determine initial vs final orphans
    mapfile -t new_orphans < <(
        comm -13 \
        <(sort <<< "$initial_orphans") \
        <(sort <<< "$final_orphans")
    )

    if [[ ${#new_orphans[@]} -gt 0 ]]; then
        echo "New orphaned packages created by this operation:"
        printf '  - %s\n' "${new_orphans[@]}"
        echo
        read -rp "Remove these new orphaned packages? [y/N] " confirm_orphans
        if [[ "$confirm_orphans" =~ ^[Yy]$ ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY-RUN] Would remove new orphaned packages."
            else
                sudo pacman -Rns "${new_orphans[@]}"
            fi
        else
            echo "Skipping new orphan removal."
        fi
    else
        echo "No new orphaned packages detected."
    fi
}


if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "Package list file not found: $PACKAGE_FILE"
    exit 1
fi

echo "==================================="
echo "Package removal audit initialized."
echo "Reading target packages from: $PACKAGE_FILE"
[[ "$DRY_RUN" == true ]] && echo "*** DRY_RUN MODE ENABALED ***"
echo "-----------------------------------"

mapfile -t all_packages < <(grep -Ev '^\s*#|^\s*$' "$PACKAGE_FILE")

if [[ ${#all_packages[@]} -eq 0 ]]; then
    echo "No valid package names found in file."
    exit 0
fi

echo "Target packages to evaluate:"
for pkg in "${all_packages[@]}"; do
    echo "  - $pkg"
done
echo "==================================="

installed=()
not_installed=()

for pkg in "${all_packages[@]}"; do
    if pacman -Q "$pkg" &>/dev/null; then
        installed+=("$pkg")
    else
        not_installed+=("$pkg")
    fi
done

# Summary
echo "====== Package Check Summary ======"

echo "Installed packages:"
if [[ ${#installed[@]} -eq 0 ]]; then
    echo "  (none found)"
else
    printf '  - %s\n' "${installed[@]}"
fi
echo
echo "Packages not installed:"
printf '  - %s\n' "${not_installed[@]}"
echo "==================================="

# Exit early if nothing to do
if [[ ${#installed[@]} -eq 0 ]]; then
    echo "No installed packages to remove."
    exit 0
fi

# Run pre-removal hooks
pre_removal_hook

# Remove installed packages
read -rp "Do you want to remove the installed packages? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Simulating removal of packages: ${installed[*]}"
    else
        sudo pacman -Rns "${installed[@]}"
    fi
else
    echo "Aborted. No packages were removed."
    exit 0
fi

# Run post-removal hooks
post_removal_hook