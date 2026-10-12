#!/usr/bin/env bash
# Claude Code status line, sur une seule ligne :
#   dossier courant | modèle effort jauge de contexte | ❺ quota 5h ❼ quota hebdo | coût | version
#
# Prérequis : bash ≥ 5, jq, coreutils GNU (stat -c, timeout) ; npm (facultatif,
# pour signaler une version plus récente de Claude Code).
#
# Réglages facultatifs (variables d'environnement) :
#   CLAUDE_STATUSLINE_PROJECTS_DIRS  dossiers de projets séparés par « : », affichés
#                                    sous forme d'icône suivie du chemin relatif
#   CLAUDE_STATUSLINE_PROJECTS_ICON  icône de ces dossiers (défaut 🛠️)
#   CLAUDE_STATUSLINE_THEME          light | dark : couleurs de l'effort (défaut :
#                                    réglage clair/sombre de GNOME, sinon light)

input=$(cat)

# Longueurs et découpages de texte en CARACTÈRES (${#…}, ${…:i:1}, indices ₕ ₘ) :
# il faut une locale UTF-8, sinon bash compte des octets et décale les textes.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
    *) export LC_ALL=C.UTF-8 ;;
esac

# Sans jq, aucun champ n'est lisible : un avertissement plutôt qu'une ligne vide.
if ! command -v jq >/dev/null; then
    printf '\033[33m⚠ status line : jq introuvable, à installer (paquet jq)\033[0m\n'
    exit 0
fi

# --- Champs du JSON fourni par Claude Code ---
# Un seul jq (le script tourne toutes les 5 s dans chaque session), une valeur
# par ligne : un champ absent donne une ligne vide, pas `empty`, pour que les
# lignes suivantes restent à leur place.
{
    IFS= read -r cwd
    IFS= read -r model
    IFS= read -r effort        # absent si le modèle ne gère pas l'effort
    IFS= read -r used_pct
    IFS= read -r ctx_tokens    # taille du contexte (dernier échange : entrée + cache), sinon déduite du %
    IFS= read -r cur_ver
    IFS= read -r cost_usd      # coût de la session en tarif API (indicatif sous abonnement)
    # Quotas 5h et hebdo : used_percentage (0-100) et resets_at (epoch s), absents
    # tant qu'aucune réponse API n'a renseigné les limites.
    IFS= read -r five_pct
    IFS= read -r five_reset_s
    IFS= read -r week_pct
    IFS= read -r week_reset_s
} < <(jq -r '
    def num(f): if type == "number" then f else "" end;
    .cwd // "",
    .model.display_name // "Unknown",
    .effort.level // "",
    .context_window.used_percentage // "",
    (.context_window | .total_input_tokens
        // (if .used_percentage and .context_window_size then .used_percentage * .context_window_size / 100 else null end)
        | num(floor)),
    .version // "",
    .cost.total_cost_usd // "",
    (.rate_limits.five_hour.used_percentage | num(round)),
    (.rate_limits.five_hour.resets_at | num(floor)),
    (.rate_limits.seven_day.used_percentage | num(round)),
    (.rate_limits.seven_day.resets_at | num(floor))
' <<<"$input")
now_s=$EPOCHSECONDS

# --- Compte connecté : absent du JSON, lu dans la config de Claude Code ---
# Chaque profil (CLAUDE_CONFIG_DIR) a son propre .claude.json. Caractères de
# contrôle retirés : ces textes finissent tels quels dans le terminal.
{
    IFS= read -r account_id
    IFS= read -r account_email
    IFS= read -r account_name
    IFS= read -r account_org
} < <(jq -r '
    def clean: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; "");
    .oauthAccount // {} | (.accountUuid // ""), (.emailAddress // ""), (.displayName // ""), (.organizationName // "") | clean
' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null)

# --- Dossier courant : ~ pour le home, icône pour les dossiers de projets ---
cwd_short="$cwd"
[[ "$cwd" == "$HOME" || "$cwd" == "$HOME"/* ]] && cwd_short="~${cwd#"$HOME"}"
PROJECTS_ICON="${CLAUDE_STATUSLINE_PROJECTS_ICON:-🛠️}"
IFS=':' read -ra projects_dirs <<<"${CLAUDE_STATUSLINE_PROJECTS_DIRS:-}"
for d in "${projects_dirs[@]}"; do
    d="${d%/}"
    [ -n "$d" ] || continue
    if [[ "$cwd" == "$d" ]]; then
        cwd_short="$PROJECTS_ICON /"; break
    elif [[ "$cwd" == "$d"/* ]]; then
        cwd_short="$PROJECTS_ICON  ${cwd#"$d"/}"; break
    fi
done

# --- ANSI codes ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[32m'
BLUE=$'\033[34m'

# --- Palette H des jauges (contexte, ❺ et ❼) : 9 niveaux, RGB fixes ---
# Indépendante de la palette du terminal (dont le jaune vif est olive).
# Seuils = valeur haute de proj (Q%/T% en %) de chaque niveau ; au-delà du
# dernier -> violet. Beaucoup de vert en bas, couleurs 3 à 7 réparties
# uniformément entre 81 et 105 ; l'équilibre (100) est orange.
#                  vert foncé  vert        vert clair   jaune      ambre      orange     rouge       cramoisi    violet
QUOTA_COLORS=(     "30;142;62" "76;175;80" "139;195;74" "240;200;0" "255;160;0" "255;109;0" "229;57;53" "194;24;91" "123;31;162")
QUOTA_GLYPHS=(     "↓"         "↓"         "↘"          "↘"         "↘"         "→"        "↗"         "↑"         "↟")
QUOTA_THRESHOLDS=( 75          81          86           91          95          100        105         110)
# Jauge de contexte : même palette, seuils en MILLIERS DE TOKENS, calés sur le
# coût des tours : /compact conseillé dès 150-200K (orange 175-200K), les tours
# > 200K pèsent l'essentiel du coût (rouge au-delà), un tour > 400K coûte ~3 fois
# un tour à 100-200K (violet au-delà).
CTX_THRESHOLDS=(   60          90          120          150         175         200        300         400)
TRACK=$'\033[48;5;250m'           # fond gris clair = piste des jauges
TRACK_RGB="188;188;188"           # même gris (250) en RGB
ELAPSED_RGB="148;148;148"         # gris plus foncé (246) : temps écoulé sans consommation
LIGHT=$'\033[38;5;248m'               # gris clair : coût, version et leur séparateur
LIGHT_YELLOW=$'\033[38;2;222;196;96m'  # jaune clair : version installée quand une plus récente existe

# --- Couleur de texte à contraste modéré sur un fond "r;g;b" (dans REPLY) ---
# Teinte du fond assombrie de moitié, ou éclaircie à 70 % vers le blanc si le
# fond est foncé : le texte se lit sans écraser la jauge.
contrast_text() {
    local r g b lum
    IFS=';' read -r r g b <<<"$1"
    lum=$(( (2126 * r + 7152 * g + 722 * b) / 10000 ))
    if (( lum > 110 )); then
        REPLY="$(( r / 2 ));$(( g / 2 ));$(( b / 2 ))"
    else
        REPLY="$(( r + (255 - r) * 7 / 10 ));$(( g + (255 - g) * 7 / 10 ));$(( b + (255 - b) * 7 / 10 ))"
    fi
}

# --- Jauge double : quota (Q) et temps écoulé (T) dans les mêmes cases ---
# $1 = Q en huitièmes, $2 = T en huitièmes, $3 = largeur en caractères,
# $4 = couleur du niveau "r;g;b". Segments, au 1/8 de case :
#   [0, min(Q,T))  couleur du niveau
#   [T, Q)         si Q > T : quota consommé en avance sur le temps -> niveau assombri de 30 %
#   [Q, T)         si T > Q : temps écoulé sans consommation -> gris plus foncé que la piste
#   au-delà        piste
# Une case ne montre qu'une frontière (▏…▉ : couleur de gauche en avant-plan, de
# droite en fond). Si Q et T tombent dans la même case, la frontière la plus
# proche de son bord extérieur y est déplacée (au plus 1/2 case, ordre Q/T
# préservé, à égalité on déplace T) : on fausse un peu les positions absolues
# pour garder lisible leur position relative.
# $5 (optionnel) = texte posé DANS la jauge (fin de fenêtre), sur des cases
# uniformes, comme le % de la jauge de contexte : calé à droite de la partie
# pleine (quota + temps), sinon à gauche de la partie vide (piste), sinon à la
# position libre la plus à droite. Si aucune ne convient, on prend la position la
# plus proche de la première qui recouvre le moins de frontières : celles-ci
# sont alors arrondies à la case (couleur du milieu de la case).
# Texte à contraste modéré (contrast_text), gris moyen sur la piste.
gauge_dual() {
    local q="$1" t="$2" cells="$3" main="$4" text="${5:-}" max=$(( $3 * 8 ))
    local mid r g b lo hi i s e left right out="" len=${#5} start=-1 cand c cost best
    local BLOCKS=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
    local -a K=()
    (( q < 0 )) && q=0; (( q > max )) && q=$max
    (( t < 0 )) && t=0; (( t > max )) && t=$max
    if (( q / 8 == t / 8 && q % 8 && t % 8 && q != t )); then
        if (( q < t )); then
            if (( q % 8 < 8 - t % 8 )); then q=$(( q / 8 * 8 )); else t=$(( (t / 8 + 1) * 8 )); fi
        else
            if (( t % 8 <= 8 - q % 8 )); then t=$(( t / 8 * 8 )); else q=$(( (q / 8 + 1) * 8 )); fi
        fi
    fi
    if (( q > t )); then
        IFS=';' read -r r g b <<<"$main"
        mid="$(( r * 7 / 10 ));$(( g * 7 / 10 ));$(( b * 7 / 10 ))"
        lo=$t; hi=$q
    else
        mid="$ELAPSED_RGB"; lo=$q; hi=$t
    fi
    # Couleur du huitième $1, renvoyée dans REPLY (pas de sous-processus).
    _gauge_dual_at() {
        if (( $1 < lo )); then REPLY=$main; elif (( $1 < hi )); then REPLY=$mid; else REPLY=$TRACK_RGB; fi
    }
    # Frontière de chaque case : K[i] = 1..7, ou 0 si la case est uniforme.
    for (( i = 0; i < cells; i++ )); do
        s=$(( i * 8 )); e=$(( s + 8 ))
        if (( lo > s && lo < e )); then K[i]=$(( lo - s ))
        elif (( hi > s && hi < e )); then K[i]=$(( hi - s ))
        else K[i]=0; fi
    done
    # Position du texte (cases [start, start+len) toutes uniformes).
    _gauge_dual_free() {
        local j
        (( $1 >= 0 && $1 + len <= cells )) || return 1
        for (( j = $1; j < $1 + len; j++ )); do (( K[j] )) && return 1; done
        return 0
    }
    if (( len > 0 && len <= cells )); then
        cand=( $(( hi / 8 - len )) $(( (hi + 7) / 8 )) )   # droite du plein, gauche du vide
        for c in "${cand[@]}"; do
            _gauge_dual_free "$c" && { start=$c; break; }
        done
        for (( c = cells - len; start < 0 && c >= 0; c-- )); do   # position libre la plus à droite
            _gauge_dual_free "$c" && start=$c
        done
        if (( start < 0 )); then   # repli : le moins de frontières, au plus près du 1er candidat
            best=999999
            for (( c = 0; c <= cells - len; c++ )); do
                cost=0
                for (( i = c; i < c + len; i++ )); do (( K[i] )) && cost=$(( cost + 1 )); done
                cost=$(( cost * 100 + (c > cand[0] ? c - cand[0] : cand[0] - c) ))
                (( cost < best )) && { best=$cost; start=$c; }
            done
        fi
    fi
    for (( i = 0; i < cells; i++ )); do
        s=$(( i * 8 ))
        if (( start >= 0 && i >= start && i < start + len )); then
            _gauge_dual_at $(( s + 4 )); left=$REPLY   # case arrondie si frontière
            if [ "$left" = "$TRACK_RGB" ]; then REPLY="98;98;98"; else contrast_text "$left"; fi
            out+=$'\033[38;2;'"${REPLY};48;2;${left}m${text:i-start:1}"
        elif (( K[i] == 0 )); then
            _gauge_dual_at "$s"
            out+=$'\033[48;2;'"${REPLY}m "
        else
            _gauge_dual_at "$s"; left=$REPLY; _gauge_dual_at $(( s + 7 )); right=$REPLY
            out+=$'\033[38;2;'"${left};48;2;${right}m${BLOCKS[K[i]]}"
        fi
    done
    printf '%s%s' "$out" "$RESET"
}

# --- Jauge avec libellé : $1 = huitièmes, $2 = largeur, $3 = texte,
#     $4 = SGR avant-plan du remplissage, $5 = SGR fond du remplissage,
#     $6 = SGR du texte posé sur le remplissage ---
# Les cases pleines et vides sont dessinées par leur couleur de fond, ce qui leur
# permet de porter une lettre ; la case partielle garde son caractère ▏…▉ et n'en
# porte pas. Texte calé à DROITE dans la partie remplie s'il y tient, sinon calé à
# GAUCHE dans la partie vide (dès la première case vide). Si ni l'un ni l'autre ne
# tient (jauge trop courte), la case partielle est arrondie à la case pleine ou
# vide la plus proche (perte < 1/2 case) pour libérer la place.
TRACK_TEXT=$'\033[38;5;241m'  # texte sur la piste : gris moyen, contraste ~3,4:1
gauge_label() {
    local n="$1" cells="$2" text="$3" fill_fg="$4" fill_bg="$5" fill_text="$6"
    local len=${#text} full part start i out=""
    local BLOCKS=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
    [ "$n" -lt 0 ] && n=0
    [ "$n" -gt $(( cells * 8 )) ] && n=$(( cells * 8 ))
    full=$(( n / 8 )); part=$(( n % 8 ))
    if (( part > 0 && full < len && cells - full - 1 < len )); then
        (( part >= 4 )) && full=$(( full + 1 ))
        part=0
    fi
    if (( full >= len )); then start=$(( full - len )); else start=$(( full + (part > 0 ? 1 : 0) )); fi

    for (( i = 0; i < cells; i++ )); do
        if (( i >= start && i < start + len )); then
            if (( i < full )); then out+="${fill_bg}${fill_text}"; else out+="${TRACK}${TRACK_TEXT}"; fi
            out+="${text:i-start:1}"
        elif (( i < full )); then
            out+="${fill_bg} "
        elif (( i == full && part > 0 )); then
            out+="${fill_fg}${TRACK}${BLOCKS[part]}"
        else
            out+="${TRACK} "
        fi
        out+="${RESET}"
    done
    printf '%s' "$out"
}

# --- Effort : mêmes couleurs que le sélecteur /effort de Claude Code ---
# low=warning, medium=success, high=permission, xhigh=autoAccept (thèmes light
# et dark de Claude Code), max=arc-en-ciel (animé dans Claude Code, figé ici).
# Le thème `auto` suit le fond du terminal, que ce script (sans TTY) ne peut pas
# interroger : à défaut de CLAUDE_STATUSLINE_THEME, le réglage clair/sombre de
# GNOME sert d'indice.
rgb() { printf '\033[1;38;2;%sm' "$1"; }  # gras + couleur 24 bits, $1 = "r;g;b"

effort_display=""
if [ -n "$effort" ]; then
    theme="${CLAUDE_STATUSLINE_THEME:-}"
    if [ -z "$theme" ] && [ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" = "'prefer-dark'" ]; then
        theme=dark
    fi
    if [ "$theme" = dark ]; then
        EFF_LOW="255;193;7";  EFF_MEDIUM="78;186;101"; EFF_HIGH="177;185;249"; EFF_XHIGH="175;135;255"
    else
        EFF_LOW="150;108;30"; EFF_MEDIUM="44;122;57";  EFF_HIGH="87;105;247";  EFF_XHIGH="135;0;255"
    fi
    case "$effort" in
        low)    effort_display="$(rgb "$EFF_LOW")low" ;;
        medium) effort_display="$(rgb "$EFF_MEDIUM")medium" ;;
        high)   effort_display="$(rgb "$EFF_HIGH")high" ;;
        xhigh)  effort_display="$(rgb "$EFF_XHIGH")xhigh" ;;
        max)    effort_display="$(rgb '250;195;95')m$(rgb '145;200;130')a$(rgb '130;170;220')x" ;;
        *)      effort_display="${GREEN}${effort}" ;;
    esac
    effort_display+="${RESET}"
fi

# --- Alternance des textes toutes les 5 s, calée sur l'horloge ---
# Pas de compteur : les relances déclenchées par les messages ne cassent pas le
# rythme (refreshInterval = 5 s). Sert aux fins de fenêtre ❺/❼ :
# 0 = heure de fin, 1 = compte à rebours.
ALT_PHASE=$(( now_s / 5 % 2 ))

# --- Context percentage ---
if [ -n "$used_pct" ]; then
    used_int=$(LC_ALL=C printf "%.0f" "$used_pct")

    # Couleur selon la TAILLE du contexte en tokens (CTX_THRESHOLDS), pas selon le
    # % : sur une fenêtre de 1M, le moment de compacter (150-200K) n'est qu'à
    # 15-20 % de remplissage. Texte posé sur le remplissage à contraste modéré.
    lv=0
    if [[ "$ctx_tokens" =~ ^[0-9]+$ ]]; then
        for t in "${CTX_THRESHOLDS[@]}"; do
            (( ctx_tokens / 1000 <= t )) && break
            lv=$(( lv + 1 ))
        done
    fi
    contrast_text "${QUOTA_COLORS[lv]}"
    PCT_COLOR=$'\033[38;2;'"${QUOTA_COLORS[lv]}m"
    PCT_BG=$'\033[48;2;'"${QUOTA_COLORS[lv]}m"
    PCT_TEXT=$'\033[38;2;'"${REPLY}m"

    # Jauge de 10 caractères = 80 crans (1,25 % chacun), comme les fenêtres ❺/❼,
    # portant la valeur exacte du %.
    pct_display=$(gauge_label $(( used_int * 80 / 100 )) 10 "${used_int}%" "$PCT_COLOR" "$PCT_BG" "$PCT_TEXT")
else
    pct_display="${DIM}N/A${RESET}"
fi

# --- Quotas partagés entre sessions ---
# Les quotas sont communs à toutes les sessions, mais chacune ne reçoit
# rate_limits qu'à SES réponses API : une session inactive garderait un Q figé
# pendant qu'une autre consomme. Un fichier commun garde, par fenêtre, le relevé
# le plus à jour : fenêtre la plus récente (resets_at le plus grand), et à
# fenêtre égale le Q le plus haut (il ne fait que croître dans une fenêtre).
# Format : une ligne « clé Q resets_at » par fenêtre.
# Un fichier par compte : chaque compte a ses propres quotas.
RL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/rate-limits"
[[ "$account_id" =~ ^[0-9A-Fa-f-]+$ ]] && RL_CACHE+="-$account_id"
declare -A RL_PCT=() RL_RESET=()
if [ -r "$RL_CACHE" ]; then
    while read -r k p r; do
        # Valeurs entières uniquement : rien d'autre n'entre dans l'arithmétique.
        [[ "$k" =~ ^(five_hour|seven_day)$ && "$p" =~ ^[0-9]+$ && "$r" =~ ^[0-9]+$ ]] || continue
        RL_PCT[$k]=$p; RL_RESET[$k]=$r
    done < "$RL_CACHE"
fi
rl_changed=0
rl_merge() {  # $1 = clé, $2 = Q vu par cette session, $3 = resets_at vu par cette session
    local k="$1" p="$2" r="$3"
    [[ "$p" =~ ^[0-9]+$ && "$r" =~ ^[0-9]+$ ]] || return 0
    if [ -z "${RL_RESET[$k]:-}" ] || (( r > RL_RESET[$k] )) \
        || { (( r == RL_RESET[$k] )) && (( p > RL_PCT[$k] )); }; then
        RL_PCT[$k]=$p; RL_RESET[$k]=$r; rl_changed=1
    fi
}
rl_merge five_hour "$five_pct" "$five_reset_s"
rl_merge seven_day "$week_pct" "$week_reset_s"
if (( rl_changed )); then
    # Écriture atomique : plusieurs sessions rafraîchissent en parallèle.
    if mkdir -p "${RL_CACHE%/*}" 2>/dev/null && rl_tmp=$(mktemp "$RL_CACHE.XXXXXX" 2>/dev/null); then
        for k in "${!RL_PCT[@]}"; do printf '%s %s %s\n' "$k" "${RL_PCT[$k]}" "${RL_RESET[$k]}"; done > "$rl_tmp" \
            && mv -f "$rl_tmp" "$RL_CACHE" || rm -f "$rl_tmp"
    fi
fi
five_pct="${RL_PCT[five_hour]:-}"; five_reset_s="${RL_RESET[five_hour]:-}"
week_pct="${RL_PCT[seven_day]:-}"; week_reset_s="${RL_RESET[seven_day]:-}"

# --- Dernière version publiée (cache d'une heure) ---
# Dans le cache de l'utilisateur, pas dans /tmp où un autre compte pourrait créer
# le fichier à l'avance.
VER_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/latest-version"
# Registre injoignable : npm peut attendre plusieurs minutes. La requête part donc
# en arrière-plan (le résultat sert au rafraîchissement suivant), et la tentative
# est marquée d'avance (touch) : réussie ou non, la suivante a lieu dans une heure.
if [ ! -f "$VER_CACHE" ] || [ $(( now_s - $(stat -c %Y "$VER_CACHE" 2>/dev/null || echo 0) )) -gt 3600 ]; then
    if mkdir -p "${VER_CACHE%/*}" 2>/dev/null && touch "$VER_CACHE" 2>/dev/null; then
        (
            ver_tmp=$(mktemp "$VER_CACHE.XXXXXX") || exit
            if timeout 30 npm view @anthropic-ai/claude-code version >"$ver_tmp"; then
                mv -f "$ver_tmp" "$VER_CACHE"
            else
                rm -f "$ver_tmp"
            fi
        ) </dev/null >/dev/null 2>&1 &
    fi
fi
latest_ver=""
[ -f "$VER_CACHE" ] && latest_ver=$(tr -d '[:space:]' <"$VER_CACHE")
# Affichée telle quelle dans le terminal : rien d'autre qu'un numéro de version.
[[ "$latest_ver" =~ ^[0-9]+(\.[0-9]+)*$ ]] || latest_ver=""

changelog_link() {
    local ver="$1" anchor
    anchor="${ver//./}"
    printf '\033]8;;https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#%s\033\\%s\033]8;;\033\\' "$anchor" "$ver"
}

if [ -n "$cur_ver" ]; then
    cur_link=$(changelog_link "$cur_ver")
    # Seulement vers une version PLUS RÉCENTE : juste après une mise à jour, le
    # cache (1 h) peut encore annoncer l'ancienne.
    if [ -n "$latest_ver" ] && [ "$cur_ver" != "$latest_ver" ] \
        && [ "$(printf '%s\n' "$cur_ver" "$latest_ver" | sort -V | tail -n 1)" = "$latest_ver" ]; then
        latest_link=$(changelog_link "$latest_ver")
        version_display="${LIGHT}v${RESET}${LIGHT_YELLOW}${cur_link}${RESET}${LIGHT}→ ${latest_link}${RESET}"
    else
        version_display="${LIGHT}v${cur_link}${RESET}"
    fi
else
    version_display=""
fi

# --- Bloc d'une fenêtre de quota : jauge double quota/temps + flèche de projection · fin ---
# $1 = quota consommé en % (entier), $2 = fin de fenêtre en epoch s (peut être vide),
# $3 = type de fenêtre : 5h (défaut) ou 7d.
window_block() {
    local window_pct="$1" reset_s="$2" kind="${3:-5h}" window_len_s
    local window_elapsed_pct="" window_eighths="" start_s elapsed eighths proj
    local out
    case "$kind" in
        7d) window_len_s=604800 ;;  # fenêtre hebdo fixe (ancrée par resets_at)
        *)  window_len_s=18000  ;;  # fenêtre 5h fixe (ancrée par resets_at)
    esac

    # --- Fenêtre expirée ---
    # rate_limits n'est mis à jour qu'à la réponse API suivante : passé resets_at,
    # le dernier relevé décrit une fenêtre terminée. On l'affiche comme telle
    # (piste vide portant « --:-- », même largeur que d'habitude, l'espace tenant
    # la place de la flèche en 5h) ; la fenêtre suivante ne démarrera qu'au
    # prochain message.
    if [ -n "$reset_s" ] && (( now_s >= reset_s )); then
        printf '%s' "$(gauge_dual 0 0 10 "$TRACK_RGB" "--:--")"
        [ "$kind" = 7d ] || printf ' '
        return
    fi

    # Temps écoulé dans la fenêtre, calculé à MAINTENANT (pas à l'heure de la réponse API) :
    # la fenêtre est fixe, ancrée par resets_at -> début = resets_at - durée.
    # Sert à calculer le rythme de consommation (projection), et à
    # dessiner la jauge de progression (en huitièmes de caractère).
    if [ -n "$reset_s" ]; then
        start_s=$(( reset_s - window_len_s ))
        elapsed=$(( (now_s - start_s) * 100 / window_len_s ))
        [ "$elapsed" -lt 1 ] && elapsed=1      # garde-fou division
        [ "$elapsed" -gt 100 ] && elapsed=100
        window_elapsed_pct="$elapsed"
        eighths=$(( (now_s - start_s) * 80 / window_len_s ))  # 0..80, cran = 3 min 45 s (5h) / 2h06 (7d)
        [ "$eighths" -lt 0 ] && eighths=0
        [ "$eighths" -gt 80 ] && eighths=80
        window_eighths="$eighths"
    fi

    # --- Couleur de la jauge = RYTHME de consommation, pas valeur absolue ---
    # On compare le quota consommé au temps écoulé dans la fenêtre.
    # Être à 90% de quota à 90% du temps (ratio ~1) est sain ; être à 80%
    # à 20% du temps (ratio 4) est alarmant. La projection = quota extrapolé
    # à 100% du temps = quota * 100 / temps_écoulé ; elle sert aux DEUX signaux.
    # 5h : durée minimale T_eff = max(T, 20 %), soit 1h. En tout début de
    #      fenêtre, quelques minutes écoulées feraient exploser la projection :
    #      on la calcule comme si au moins 1h était écoulée. C'est continu (pas de
    #      seuil sur Q) et une vraie rafale reste signalée (24 % en 15 min -> 120).
    # 7d : pas de durée minimale.
    if [ -n "$window_elapsed_pct" ]; then   # toujours ≥ 1 : pas de division par zéro
        local t_eff="$window_elapsed_pct"
        [ "$kind" != 7d ] && (( t_eff < 20 )) && t_eff=20
        proj=$(( window_pct * 100 / t_eff ))   # quota projeté fin de fenêtre
    else
        proj="$window_pct"
    fi

    # --- Niveau de PROJECTION (quota à fin de fenêtre) : palette H à 9 niveaux ---
    # proj = Q% * 100 / T% : « Q% à 80 % de T% » <=> proj = 80.
    # Le niveau colore le remplissage de la jauge et choisit, en 5h, la flèche
    # placée juste après elle (↓ on finira large / → à l'équilibre / ↑ on tape le mur avant reset).
    # 7d : couleur seule, sans flèche.
    local lv=0 t
    for t in "${QUOTA_THRESHOLDS[@]}"; do
        [ "$proj" -le "$t" ] && break
        lv=$(( lv + 1 ))
    done
    # --- Fin de fenêtre, posée DANS la jauge ---
    # En alternance (ALT_PHASE), la fin de fenêtre ou le temps restant (arrondi
    # au-dessus), avec les indices ₕ et ₘ :
    #   5h : heure de fin « 14:05 » / reste « 1ₕ07ₘ », « 42ₘ » sous l'heure
    #   7d : jour+heure de fin « Sa22ₕ » / reste « 2ⱼ14ₕ », « 5ₕ » sous le jour
    # La longueur varie (2 à 5 caractères) sans rien décaler : le texte est dans la jauge.
    local end_text=""
    if [ -n "$window_eighths" ]; then
        local remain_s=$(( reset_s - now_s )) remain_m remain_h dow
        local DAYS=(Lu Ma Me Je Ve Sa Di)
        [ "$remain_s" -lt 0 ] && remain_s=0
        if [ "$kind" = 7d ]; then
            if (( ALT_PHASE == 0 )); then
                printf -v dow '%(%u)T' "$reset_s"
                printf -v end_text '%s%(%H)Tₕ' "${DAYS[dow - 1]}" "$reset_s"
            else
                remain_h=$(( (remain_s + 3599) / 3600 ))
                if (( remain_h >= 24 )); then
                    printf -v end_text '%dⱼ%02dₕ' $(( remain_h / 24 )) $(( remain_h % 24 ))
                else
                    end_text="${remain_h}ₕ"
                fi
            fi
        elif (( ALT_PHASE == 0 )); then
            printf -v end_text '%(%H:%M)T' "$reset_s"
        else
            remain_m=$(( (remain_s + 59) / 60 ))
            if (( remain_m >= 60 )); then
                printf -v end_text '%dₕ%02dₘ' $(( remain_m / 60 )) $(( remain_m % 60 ))
            else
                end_text="${remain_m}ₘ"
            fi
        fi
    fi

    # --- Jauge double quota/temps : 10 caractères = 80 crans (1,25 % chacun) ---
    # Sans fin de fenêtre connue, le temps est inconnu : quota seul (T = Q).
    local nq=$(( window_pct * 80 / 100 ))
    out=$(gauge_dual "$nq" "${window_eighths:-$nq}" 10 "${QUOTA_COLORS[lv]}" "$end_text")

    # --- Flèche de tendance (5h), juste après la jauge, couleur du niveau ---
    [ "$kind" = 7d ] || out+=$'\033[38;2;'"${QUOTA_COLORS[lv]}m${QUOTA_GLYPHS[lv]}${RESET}"
    printf '%s' "$out"
}

# Préfixe collé à la jauge ; l'espace n'est gardée que devant « N/A ».
window_display="${DIM}❺${RESET}"
if [ -n "$five_pct" ]; then
    window_display+=$(window_block "$five_pct" "$five_reset_s" 5h)
else
    window_display+=" ${DIM}N/A${RESET}"
fi
if [ -n "$week_pct" ]; then
    window_display+=" ${DIM}❼${RESET}$(window_block "$week_pct" "$week_reset_s" 7d)"
fi

# --- Coût API ---
session_display=""
if [ -n "$cost_usd" ]; then
    session_display="${LIGHT}$(LC_ALL=C printf '$%.2f' "$cost_usd")${RESET}"
fi

# --- Separators ---
SEP="${DIM} | ${RESET}"
LIGHT_SEP="${LIGHT} | ${RESET}"  # entre coût et version, aussi clair qu'eux

# --- Output (single line) ---
printf '%s' "${BOLD}${BLUE}${cwd_short}${RESET}"
printf '%s' "${SEP}"
printf '%s' "${BOLD}${GREEN}${model}${RESET}"
if [ -n "$effort_display" ]; then
    printf '%s' " ${effort_display}"
fi
printf ' '
printf '%s' "${pct_display}"
printf '%s' "${SEP}"
printf '%s' "${window_display}"
if [ -n "$session_display" ]; then
    printf '%s' "${SEP}"
    printf '%s' "${session_display}"
fi
if [ -n "$version_display" ]; then
    if [ -n "$session_display" ]; then printf '%s' "${LIGHT_SEP}"; else printf '%s' "${SEP}"; fi
    printf '%s' "${version_display}"
fi
printf '\n'
