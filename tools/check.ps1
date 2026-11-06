# Vérification complète sous Windows (PowerShell).
# Usage :  .\tools\check.ps1 -Godot "C:\Godot\Godot_v4.3-stable_win64_console.exe"
# Utiliser l'exécutable *_console.exe pour voir les messages dans le terminal.
param([string]$Godot = "godot", [switch]$Monde)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "== Import du projet =="
$log = & $Godot --headless --import 2>&1 | Out-String
Write-Host $log
if ($log -match "SCRIPT ERROR|Parse Error|Failed to load") {
    Write-Error "Echec : erreurs pendant l'import."
    exit 1
}

Write-Host "== Tests =="
& $Godot --headless -s tests/run_checks.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "== Tests du Lot 4 (generation structurelle) =="
& $Godot --headless -s tests/run_checks_lot4.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "== Tests du Lot 5 (ile d'ouverture) =="
& $Godot --headless -s tests/run_checks_lot5.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "== Tests du Lot 6 (laboratoire developpeur) =="
& $Godot --headless -s tests/run_checks_lot6.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "== Tests du Lot 7 (plan, terrain, editeur de carte) =="
& $Godot --headless -s tests/run_checks_lot7.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "== Tests du Lot 8 (construction, atelier, maisons) =="
& $Godot --headless -s tests/run_checks_lot8.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "== Tests du Lot 9 (habitations, placement automatique, composition) =="
& $Godot --headless -s tests/run_checks_lot9.gd
Write-Host "== Tests du Lot 10 (remodelage de l'ile d'ouverture) =="
& $Godot --headless -s tests/run_checks_lot10.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Monde) {
    Write-Host "== Iles completes : validation multi-graines et profils =="
    & $Godot --headless -s tests/run_checks_lot4.gd -- --monde
}
exit $LASTEXITCODE