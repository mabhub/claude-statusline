#!/usr/bin/env bash
# Claude Code status line — mode AUTO (adaptatif à la hauteur du terminal).
#
# Claude Code (>= v2.1.153) exporte la hauteur réelle du terminal dans $LINES
# avant chaque exécution du script statusLine.
#   - Hauteur < STATUSLINE_MIN_LINES  -> rien (0 ligne, on récupère la place).
#   - Hauteur >= seuil                -> status line complète (statusline.sh).
#
# Caveat connu : le script n'est ré-exécuté qu'aux triggers Claude Code
# (nouveau message, /compact, changement de mode permission, vim toggle), PAS
# sur redimensionnement (SIGWINCH). Après un resize, l'affichage se réajuste
# au prochain de ces évènements.
#
# Seuil réglable via la variable d'env CLAUDE_STATUSLINE_MIN_LINES (défaut 15).

set -euo pipefail

THRESHOLD="${CLAUDE_STATUSLINE_MIN_LINES:-15}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# $LINES est fourni par Claude Code. S'il manque (ancienne version, exécution
# hors harness), on retombe sur l'affichage complet plutôt que de tout masquer.
rows="${LINES:-}"
if [[ -z "$rows" || ! "$rows" =~ ^[0-9]+$ ]]; then
    rows=999
fi

# stdin (le JSON) doit être consommé une seule fois puis transmis au script délégué.
input="$(cat)"

if (( rows < THRESHOLD )); then
    # Écran trop petit : aucune sortie -> aucune ligne réservée.
    exit 0
fi

# Sinon : status line complète. On lui réinjecte le JSON sur stdin.
printf '%s' "$input" | "$DIR/statusline.sh"
