# claude-statusline

Status line d'une ligne pour [Claude Code](https://code.claude.com/docs/en/statusline),
écrite en bash. Elle affiche d'un coup d'œil le dossier courant, le modèle et
son niveau d'effort, le remplissage du contexte, la consommation des quotas
d'abonnement (fenêtre de 5 h et hebdomadaire), le coût de la session et la
version de Claude Code.

```
🛠️  mon-projet | Opus 5.5 high [12%      ] | ❺[████1ₕ07ₘ  ]↓ ❼[█2ⱼ08ₕ    ] | $3.21 | v2.1.300→ 2.1.301
```

(Aperçu approximatif : les jauges sont dessinées en couleurs 24 bits.)

## Ce qui est affiché

| Segment          | Contenu                                                                                                                                                                                                                                                                                                                                                                                         |
|------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Dossier          | Chemin courant, `~` pour le home. Les dossiers de projets peuvent être remplacés par une icône (voir [Réglages](#réglages)).                                                                                                                                                                                                                                                                    |
| Modèle et effort | Nom du modèle, puis le niveau d'effort coloré comme dans le sélecteur `/effort` de Claude Code.                                                                                                                                                                                                                                                                                                 |
| Contexte         | Jauge de 10 caractères portant le % de remplissage. La couleur dépend de la **taille** du contexte en tokens, pas du % : vert jusqu'à 120K, jaune/ambre jusqu'à 175K, orange jusqu'à 200K (moment de faire `/compact`), rouge au-delà, violet après 400K.                                                                                                                                       |
| ❺ quota 5 h      | Jauge double : quota consommé et temps écoulé dans la fenêtre, dans les mêmes cases. La couleur et la flèche (↓ ↘ → ↗ ↑ ↟) donnent la projection du quota en fin de fenêtre au rythme actuel → vert = large marge, orange = pile à 100 %, rouge/violet = quota épuisé avant la fin. Le texte dans la jauge alterne toutes les 5 s entre l'heure de fin (`14:05`) et le temps restant (`1ₕ07ₘ`). |
| ❼ quota hebdo    | Même jauge pour la fenêtre de 7 jours, sans flèche (`Sa22ₕ` ↔ `2ⱼ08ₕ`).                                                                                                                                                                                                                                                                                                                         |
| Coût             | Coût de la session au tarif API (indicatif sous abonnement).                                                                                                                                                                                                                                                                                                                                    |
| Version          | Version de Claude Code, en jaune suivie de la dernière version publiée si elle est plus récente. Les numéros sont des liens vers le changelog.                                                                                                                                                                                                                                                  |

Détail de la jauge double :

- couleur pleine → quota consommé dans les temps
- couleur assombrie → quota consommé en avance sur le temps écoulé
- gris foncé → temps écoulé sans consommation
- gris clair → reste de la fenêtre

Une fenêtre terminée mais pas encore rafraîchie par Claude Code s'affiche vide
avec `--:--`.

## Prérequis

- Linux (coreutils GNU : `date -d`, `stat -c`)
- bash ≥ 5
- `jq` → sans lui, la status line affiche seulement un avertissement qui invite
  à l'installer
- un terminal en couleurs 24 bits avec une police qui contient les blocs `▏`…`▉`
  et les indices `ₕ ₘ ⱼ`
- `npm` (facultatif) → sert uniquement à détecter une nouvelle version de
  Claude Code, une fois par heure

Les quotas ❺/❼ ne s'affichent qu'avec un abonnement Claude (Pro/Max), après la
première réponse de l'API dans la session.

## Installation

1. Récupérer le script, depuis le dépôt ou l'archive :

   ```bash
   git clone <url-du-dépôt> ~/projets/claude-statusline
   # ou
   tar xzf claude-statusline.tar.gz -C ~/projets
   ```

2. Le rendre accessible depuis `~/.claude`, par lien symbolique (les mises à
   jour du dépôt sont prises en compte directement) ou par copie :

   ```bash
   ln -s ~/projets/claude-statusline/statusline.sh ~/.claude/statusline.sh
   ```

3. Déclarer la status line dans `~/.claude/settings.json` :

   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/statusline.sh",
     "refreshInterval": 5
   }
   ```

   `refreshInterval` relance le script toutes les 5 s, ce qui fait avancer les
   jauges de temps et alterner les textes même quand la session est inactive.
   Sans lui, l'affichage n'est rafraîchi qu'à chaque message.

   Ou en une commande, avec `jq` (écriture atomique, les autres réglages sont
   conservés) :

   ```bash
   f=~/.claude/settings.json
   jq '.statusLine = {type: "command", command: "~/.claude/statusline.sh", refreshInterval: 5}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
   ```

La status line apparaît au prochain rafraîchissement, sans redémarrer Claude Code.

Pour la tester hors de Claude Code :

```bash
echo '{"cwd":"'"$PWD"'","model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":12,"total_input_tokens":120000}}' \
  | ~/.claude/statusline.sh
```

## Réglages

Tous facultatifs, par variables d'environnement :

| Variable                          | Effet                                                                                                           |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------------|
| `CLAUDE_STATUSLINE_PROJECTS_DIRS` | Dossiers de projets séparés par `:`. Dedans, le chemin est affiché relatif, précédé d'une icône.                |
| `CLAUDE_STATUSLINE_PROJECTS_ICON` | Icône de ces dossiers (défaut `🛠️`).                                                                           |
| `CLAUDE_STATUSLINE_THEME`         | `light` ou `dark` → palette des couleurs d'effort. Par défaut, le réglage clair/sombre de GNOME, sinon `light`. |

Le script tourne sans terminal attaché et ne peut pas connaître le fond du
terminal → `CLAUDE_STATUSLINE_THEME` sert à l'indiquer hors de GNOME.

La façon la plus simple de les passer est de les poser dans la commande :

```json
"command": "CLAUDE_STATUSLINE_PROJECTS_DIRS=$HOME/projets CLAUDE_STATUSLINE_THEME=dark ~/.claude/statusline.sh"
```

Elles peuvent aussi être exportées dans le shell qui lance `claude`.

## Fichiers créés

- `~/.cache/claude-statusline/rate-limits` (ou sous `$XDG_CACHE_HOME`) → dernier
  relevé des quotas, partagé entre sessions. Chaque session ne reçoit les quotas
  qu'à ses propres réponses API, le fichier évite qu'une session inactive
  affiche un quota figé pendant qu'une autre consomme.
- `~/.cache/claude-statusline/latest-version` → dernière version publiée de
  Claude Code, mise en cache une heure.

## Produire une archive

```bash
git archive --format=tar.gz --prefix=claude-statusline/ -o claude-statusline.tar.gz HEAD
```
