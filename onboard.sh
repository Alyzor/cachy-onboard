#!/usr/bin/env bash
# CachyOS onboarding script
# - installs packages from apps.txt (same folder): pacman first, AUR as last resort
# - sets limine timeout to 0
# - asks which power profile you want
#
# Run as your normal user (NOT root). It uses sudo when needed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_FILE="$SCRIPT_DIR/apps.txt"
LIMINE_CONF="/boot/limine.conf"

if [[ $EUID -eq 0 ]]; then
    echo "Don't run this as root, AUR helpers refuse to work that way. Just use your normal user."
    exit 1
fi

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- packages
install_packages() {
    if [[ ! -f "$APPS_FILE" ]]; then
        warn "No apps.txt found at $APPS_FILE, skipping package install."
        return
    fi

    # pick an AUR helper (paru ships with CachyOS)
    local aur_helper=""
    if   command -v paru >/dev/null; then aur_helper="paru"
    elif command -v yay  >/dev/null; then aur_helper="yay"
    else warn "No AUR helper (paru/yay) found, AUR packages will be skipped."
    fi

    log "Syncing and updating system (avoids partial upgrades)"
    sudo pacman -Syu --noconfirm

    local pacman_pkgs=() aur_pkgs=() skipped=() missing=()

    # strip comments (#...) and blank lines, trim whitespace
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if pacman -Qq "$pkg" &>/dev/null; then
            skipped+=("$pkg")
        elif pacman -Si "$pkg" &>/dev/null || pacman -Sg "$pkg" &>/dev/null; then
            pacman_pkgs+=("$pkg")
        elif [[ -n "$aur_helper" ]] && "$aur_helper" -Si "$pkg" &>/dev/null; then
            aur_pkgs+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$APPS_FILE")

    [[ ${#skipped[@]} -gt 0 ]] && echo "Already installed: ${skipped[*]}"

    if [[ ${#pacman_pkgs[@]} -gt 0 ]]; then
        log "Installing from official repos: ${pacman_pkgs[*]}"
        sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}" || warn "Some pacman installs failed."
    fi

    if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
        log "Installing from AUR ($aur_helper): ${aur_pkgs[*]}"
        "$aur_helper" -S --needed --noconfirm "${aur_pkgs[@]}" || warn "Some AUR installs failed."
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Not found in repos or AUR: ${missing[*]}"
    fi
}

# ---------------------------------------------------------------- limine
set_limine_timeout() {
    log "Setting limine timeout to 0"
    if [[ ! -f "$LIMINE_CONF" ]]; then
        warn "$LIMINE_CONF not found, skipping (are you actually on Limine?)."
        return
    fi

    sudo cp -n "$LIMINE_CONF" "${LIMINE_CONF}.bak"

    if grep -qE '^timeout:' "$LIMINE_CONF"; then
        sudo sed -i -E 's/^timeout:.*/timeout: 0/' "$LIMINE_CONF"
    else
        # no timeout line at all, add it at the top
        sudo sed -i '1i timeout: 0' "$LIMINE_CONF"
    fi

    grep -E '^timeout:' "$LIMINE_CONF"
}

# ---------------------------------------------------------------- power mode
set_power_profile() {
    log "Power profile"
    if ! command -v powerprofilesctl >/dev/null; then
        warn "powerprofilesctl not found (install power-profiles-daemon), skipping."
        return
    fi

    # lines look like "* balanced:" or "  performance:"
    mapfile -t profiles < <(powerprofilesctl list | sed -nE 's/^[* ] ([a-z-]+):.*/\1/p')
    if [[ ${#profiles[@]} -eq 0 ]]; then
        warn "Couldn't read any power profiles, skipping."
        return
    fi

    echo "Current: $(powerprofilesctl get)"
    echo "Pick a power profile:"
    select choice in "${profiles[@]}" "skip"; do
        if [[ "$choice" == "skip" ]]; then
            echo "Leaving it as is."
            break
        elif [[ -n "$choice" ]]; then
            powerprofilesctl set "$choice" && echo "Power profile set to: $choice"
            break
        fi
        echo "Invalid choice, try again."
    done
}

# ---------------------------------------------------------------- main
install_packages
set_limine_timeout
set_power_profile

log "All done. Reboot when you're ready."
