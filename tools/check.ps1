# Vérification complète sous Windows (PowerShell).
# Usage :  .\tools\check.ps1 -Godot "C:\Godot\Godot_v4.3-stable_win64_console.exe"
# Utiliser l'exécutable *_console.exe pour voir les messages dans le terminal.
param([string]$Godot = "godot")
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
exit $LASTEXITCODE
