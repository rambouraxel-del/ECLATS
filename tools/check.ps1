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
if ($Monde) {
    Write-Host "== Iles completes : validation multi-graines et profils =="
    & $Godot --headless -s tests/run_checks_lot4.gd -- --monde
}
exit $LASTEXITCODE