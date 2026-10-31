#!/usr/bin/env bash
# Step 2: compare the Windows app list against pacman + AUR
#
# Input : windows-apps.txt (or pass a path as $1), one package guess per line
# Output: apps.txt         -> available (repo, or AUR and approved by you)
#         apps.manual.txt  -> NOT available / rejected, install these by hand
#
# Official repo hits are added automatically.
# AUR-only hits are shown to you first and you decide y/n.
#
# Updates the system first and installs yay if no AUR helper is present.
# Run as your normal user.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN="${1:-$SCRIPT_DIR/windows-apps.txt}"
OUT_OK="$SCRIPT_DIR/apps.txt"
OUT_MANUAL="$SCRIPT_DIR/apps.manual.txt"

if [[ ! -f "$IN" ]]; then
    echo "Input file not found: $IN"
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
    echo "Don't run this as root, AUR helpers (and makepkg) refuse to work that way."
    exit 1
fi

# ---- 1. update the system first (full upgrade, avoids partial-upgrade breakage)
printf '\033[1;36m==> Updating system\033[0m\n'
sudo pacman -Syu --noconfirm || echo "[!] System update had errors, continuing anyway."

# ---- 2. make sure an AUR helper exists (paru ships with CachyOS), else install yay
install_yay() {
    printf '\033[1;36m==> No paru/yay found, installing yay\033[0m\n'
    # try the repos first (CachyOS usually carries it)
    if sudo pacman -S --needed --noconfirm yay 2>/dev/null; then
        return 0
    fi
    # fall back to building yay-bin from the AUR
    sudo pacman -S --needed --noconfirm git base-devel || return 1
    local tmp
    tmp="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
        && (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    local rc=$?
    rm -rf "$tmp"
    return $rc
}

if ! command -v paru >/dev/null && ! command -v yay >/dev/null; then
    install_yay || echo "[!] Couldn't install yay."
fi

if   command -v paru >/dev/null; then HELPER="paru"
elif command -v yay  >/dev/null; then HELPER="yay"
else echo "[!] No AUR helper available, only checking official repos."; HELPER=""
fi

: > "$OUT_OK"
: > "$OUT_MANUAL"

repo=0; aur=0; rejected=0; miss=0

# ask y/n on the real terminal (stdin is busy feeding the package list)
confirm() {
    local ans
    if [[ ! -r /dev/tty ]]; then return 1; fi
    read -rp "    Add this AUR package? [y/N] " ans < /dev/tty
    [[ "$ans" =~ ^[Yy]$ ]]
}

# clean list: strip CRLF, comments, blanks, whitespace, dupes
mapfile -t PKGS < <(tr -d '\r' < "$IN" \
    | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk 'NF && !seen[$0]++')

for pkg in "${PKGS[@]}"; do
    if pacman -Si "$pkg" &>/dev/null || pacman -Sg "$pkg" &>/dev/null; then
        echo "$pkg" >> "$OUT_OK"
        printf '\033[1;32m[repo]\033[0m %s\n' "$pkg"; ((repo++))

    elif [[ -n "$HELPER" ]] && "$HELPER" -Si "$pkg" &>/dev/null; then
        printf '\033[1;35m[aur] \033[0m %s  <- only in AUR, verify:\n' "$pkg"
        "$HELPER" -Si "$pkg" 2>/dev/null \
            | grep -E '^(Name|Version|Description|URL|Votes|Popularity|Maintainer|Provides)\b' \
            | sed 's/^/      /'
        if confirm; then
            echo "$pkg" >> "$OUT_OK"
            printf '    \033[1;32mapproved\033[0m\n'; ((aur++))
        else
            echo "$pkg  # AUR match rejected/skipped, check manually" >> "$OUT_MANUAL"
            printf '    \033[1;33mskipped -> manual list\033[0m\n'; ((rejected++))
        fi

    else
        hints=""
        [[ -n "$HELPER" ]] && hints=$("$HELPER" -Ssq "$pkg" 2>/dev/null | head -3 | paste -sd' ')
        echo "$pkg  # maybe: ${hints:-nothing}" >> "$OUT_MANUAL"
        printf '\033[1;31m[miss]\033[0m %s -> %s\n' "$pkg" "${hints:-nothing}"; ((miss++))
    fi
done

echo
echo "Done: $repo repo, $aur AUR approved, $rejected AUR skipped, $miss not found"
echo "  available -> $OUT_OK"
echo "  manual    -> $OUT_MANUAL"
