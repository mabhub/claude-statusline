#!/usr/bin/env bash
# Claude Code status line — variante MINIMALE (1 ligne, hauteur réduite).
# Temporaire : pour écran à très peu de lignes visibles.
# Restaurer la version complète : repointer settings.json sur statusline.sh.
# Affiche uniquement le % de contexte (utile pour savoir quand /compact).

input=$(cat)
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

RESET=$'\033[0m'
BRIGHT_GREEN=$'\033[92m'
BRIGHT_YELLOW=$'\033[93m'
BRIGHT_RED=$'\033[91m'
DIM=$'\033[2m'

if [ -n "$used_pct" ]; then
    used_int=$(LC_ALL=C printf "%.0f" "$used_pct" 2>/dev/null)
    [ -z "$used_int" ] && used_int=0
    if [ "$used_int" -lt 50 ]; then
        COLOR="$BRIGHT_GREEN"
    elif [ "$used_int" -lt 80 ]; then
        COLOR="$BRIGHT_YELLOW"
    else
        COLOR="$BRIGHT_RED"
    fi
    printf '%s' "${COLOR}${used_int}%${RESET}"
else
    printf '%s' "${DIM}N/A${RESET}"
fi
