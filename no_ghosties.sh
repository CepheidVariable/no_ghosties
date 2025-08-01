#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage $0 --file <package_list_file> [--dry-run]"
    exit 1
}

# Default values
DRY_RUN=false
PKG_LIST_FILE=""
INITIAL_ORPHANS=()

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --file)
      PKG_LIST_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

# Helpers
installed() {
    # Check if a package is installed
    pacman -Q "$1" &>/dev/null
}

simulate_removal() {
    local pkgs=("$@")
    echo "[DRY-RUN] Simulating removal of packages..."
    
    # Simulate removal and find new orphans (dry run only)
    mapfile -t simulated_removal < <(sudo pacman -Rs --print "${pkgs[@]}")

    echo "The following packages would be removed:"
    printf '  - %s\n' "${simulated_removal[@]}"
    exit 0
}

# Pre-removal hooks
pre_removal_hook_initial_orphans() {
    # Snapshot of current orphans
    INITIAL_ORPHANS=$(pacman -Qdtq | sort)
}

# Post-removal hooks
post_removal_hook_clean_orphans() {
    final_orphans=$(pacman -Qtdq 2>/dev/null || true)

    # Determine new orphans
    mapfile -t new_orphans < <(
        comm -13 \
        <(sort <<< "$INITIAL_ORPHANS") \
        <(sort <<< "$final_orphans")
    )

    if [[ ${#new_orphans[@]} -gt 0 ]]; then
        echo "New orphaned packages created:"
        printf '  - %s\n' "${new_orphans[@]}"
        read -rp "Remove these new orphaned packages? [y/N] " confirm_orphans
        if [[ "$confirm_orphans" =~ ^[Yy]$ ]]; then
            sudo pacman -Rns "${new_orphans[@]}"
        else
            echo "Skipping orphan removal."
        fi
    fi
}

#====================MAIN SCRIPT====================
if [[ ! -f "$PKG_LIST_FILE" ]]; then
    echo "Error: File not found. Exiting."
    usage
fi

echo "==================================="
echo "Package removal audit initialized."
echo "Reading target packages from: $PKG_LIST_FILE"
[[ "$DRY_RUN" == true ]] && echo "*** DRY_RUN MODE ENABALED ***"
echo "-----------------------------------"

# Read package list from file
mapfile -t pkg_list < <(grep -Ev '^\s*#|^\s*$' "$PKG_LIST_FILE")

# Validation: No Packages in file
if [[ ${#pkg_list[@]} -eq 0 ]]; then
    echo "No valid package names found in file."
    exit 0
fi

# Print packages to evaluate; check if installed or not
remove_list=()
echo "Target packages to evaluate:"
for pkg in "${pkg_list[@]}"; do
    echo "  - $pkg"
    
    # Filter out packages which are not installed
    if installed "$pkg"; then
        remove_list+=("$pkg")
    fi
done
echo "==================================="

# Summary
echo "====== Package Check Summary ======"

echo "Installed packages:"
if [[ ${#remove_list[@]} -eq 0 ]]; then
    echo "  (none found)"
else
    printf '  - %s\n' "${remove_list[@]}"
fi
echo "==================================="

# Exit if there's nothing to remove
if [[ ${#remove_list[@]} -eq 0 ]]; then
  echo "No specified packages are installed. Exiting."
  exit 0
fi

# Run pre-removal hooks
pre_removal_hook_initial_orphans

# Dry-run
if [[ "$DRY_RUN" == true ]]; then
    simulate_removal "${remove_list[@]}"
fi

# Confirm removal
read -rp "Do you want to remove the installed packages? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Removing packages..."
    sudo pacman -Rns "${remove_list[@]}"
else
    echo "Aborted. No packages were removed."
    exit 0
fi

# Run post-removal hooks
post_removal_hook_clean_orphans
