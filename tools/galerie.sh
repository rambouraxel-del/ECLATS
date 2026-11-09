#!/usr/bin/env bash
# Actualise la galerie 3D : détecte les modèles précuits et les générateurs enregistrés, exporte les glTF
# (galerie/modeles/*.glb.gz) et le catalogue (galerie/catalogue.json).
#   GODOT=/chemin/vers/godot tools/galerie.sh [--seulement=famille] [--sortie=dossier] [--max=N]
# Aperçu local : python3 -m http.server -d galerie 8000   puis http://localhost:8000/
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT:-godot}"
OUT="galerie"
for a in "$@"; do case "$a" in --sortie=*) OUT="${a#--sortie=}";; esac; done
echo "== Import du projet =="
LOG=$(mktemp)
timeout 300 "$GODOT_BIN" --headless --import 2>&1 | tee "$LOG" || true
if grep -E "SCRIPT ERROR|Parse Error" "$LOG"; then echo "Échec : erreurs pendant l'import." >&2; exit 1; fi
echo "== Export de la galerie =="
# (les « Parameter "m" is null » du rendu factice sont un bruit connu du moteur sans écran ; sans effet sur les fichiers)
rm -rf "$OUT/modeles" "$OUT/catalogue.json"
timeout 900 "$GODOT_BIN" --headless -s tools/galerie/galerie_export.gd -- "$@" 2>&1 | tee "$LOG"
if grep -E "SCRIPT ERROR|Parse Error" "$LOG"; then echo "Échec : erreur dans l'exporteur." >&2; exit 1; fi
test -s "$OUT/catalogue.json" || { echo "Échec : catalogue absent." >&2; exit 1; }
N=$(grep -c '"fichier"' "$OUT/catalogue.json" || true)
echo "Galerie prête : $N modèles dans $OUT/ ($(du -sh "$OUT/modeles" | cut -f1))"
