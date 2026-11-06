#!/usr/bin/env bash
# Vérification complète en mode headless (Linux / macOS / CI).
#   GODOT=/chemin/vers/godot tools/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT:-godot}"
echo "== Import du projet =="
LOG=$(mktemp)
timeout 300 "$GODOT_BIN" --headless --import 2>&1 | tee "$LOG"
if grep -E "SCRIPT ERROR|Parse Error|Failed to load" "$LOG"; then
	echo "Échec : erreurs pendant l'import." >&2
	exit 1
fi
echo "== Tests =="
timeout 300 "$GODOT_BIN" --headless -s tests/run_checks.gd
echo "== Tests du Lot 4 (génération structurelle) =="
timeout 600 "$GODOT_BIN" --headless -s tests/run_checks_lot4.gd
echo "== Tests du Lot 5 (île d'ouverture) =="
timeout 300 "$GODOT_BIN" --headless -s tests/run_checks_lot5.gd
echo "== Tests du Lot 6 (laboratoire développeur) =="
timeout 600 "$GODOT_BIN" --headless -s tests/run_checks_lot6.gd
echo "== Tests du Lot 7 (plan, terrain, éditeur de carte) =="
timeout 900 "$GODOT_BIN" --headless -s tests/run_checks_lot7.gd
echo "== Tests du Lot 8 (construction, atelier, maisons) =="
timeout 900 "$GODOT_BIN" --headless -s tests/run_checks_lot8.gd
echo "== Tests du Lot 9 (habitations, placement automatique, composition) =="
timeout 900 "$GODOT_BIN" --headless -s tests/run_checks_lot9.gd
if [ "${ECLATS_MONDE:-0}" = "1" ]; then
	echo "== Îles complètes : validation multi-graines et profils (ECLATS_MONDE=1) =="
	timeout 900 "$GODOT_BIN" --headless -s tests/run_checks_lot4.gd -- --monde
fi
